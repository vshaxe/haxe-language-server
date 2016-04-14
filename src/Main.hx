import js.Node.process;
import js.node.Buffer;
import js.node.Path;
import js.node.Url;
import js.node.ChildProcess;
import js.node.child_process.ChildProcess.ChildProcessEvent;
import js.node.stream.Readable.ReadableEvent;
import jsonrpc.ErrorCodes;
import jsonrpc.node.MessageReader;
import jsonrpc.node.MessageWriter;
import vscode.ProtocolTypes;
import sys.FileSystem;
using StringTools;

typedef HaxePosition = {
    file:String,
    line:Int, // 1-based
    startLine:Null<Int>, // 1-based
    endLine:Null<Int>, // 1-based
    startByte:Null<Int>, // 0-based byte offset
    endByte:Null<Int>, // 0-based byte offset
}

class Main {
    static var positionRe = ~/^(.+):(\d+): (?:lines (\d+)-(\d+)|character(?:s (\d+)-| )(\d+))$/;

    static function parsePosition(pos:String):HaxePosition {
        return if (positionRe.match(pos))
            {
                file: positionRe.matched(1),
                line: Std.parseInt(positionRe.matched(2)),
                startLine: Std.parseInt(positionRe.matched(3)),
                endLine: Std.parseInt(positionRe.matched(4)),
                startByte: Std.parseInt(positionRe.matched(5)),
                endByte: Std.parseInt(positionRe.matched(6)),
            }
        else
            null;
    }

    static function main() {
        var reader = new MessageReader(process.stdin);
        var writer = new MessageWriter(process.stdout);

        var proto = new vscode.Protocol(writer.write);

        haxe.Log.trace = function(v, ?i) {
            var r = [Std.string(v)];
            if (i != null && i.customParams != null) {
                for (v in i.customParams)
                    r.push(Std.string(v));
            }
            proto.sendLogMessage({type: Log, message: r.join(" ")});
        }

        var rootPath;
        // var tmpDir;
        var hxmlFile;
        var haxeServer = new HaxeServer();

        var docs = new TextDocuments();
        docs.listen(proto);

        proto.onInitialize = function(params, resolve, reject) {
            rootPath = params.rootPath;

            // tmpDir = Path.join(rootPath, "tmp");
            // deleteRec(tmpDir);

            resolve({
                capabilities: {
                    textDocumentSync: Full,
                    completionProvider: {
                        triggerCharacters: ["."]
                    },
                    signatureHelpProvider: {
                        triggerCharacters: ["("]
                    }
                }
            });
        };

        proto.onShutdown = function() {
            haxeServer.stop();
        }

        proto.onDidChangeConfiguration = function(config) {
            hxmlFile = (config.settings.haxe.buildFile : String);
            haxeServer.start(6000);
        };

        // TODO: replace this with tempdir stuff
        function tempSave(uri:String, cb:TextDocument->String->(Void->Void)->Void) {
            var doc = docs.get(uri);
            var filePath = uriToFsPath(uri);
            var stats = js.node.Fs.statSync(filePath);
            var oldContent = sys.io.File.getContent(filePath);
            sys.io.File.saveContent(filePath, doc.content); 
            js.node.Fs.utimesSync(filePath, stats.atime, stats.mtime);
            cb(doc, filePath, function() {
                sys.io.File.saveContent(filePath, oldContent); 
                js.node.Fs.utimesSync(filePath, stats.atime, stats.mtime);
            });
        }

        inline function getBaseDisplayArgs() return [
            "--cwd", rootPath,
            hxmlFile, // call completion file
            // "-cp", tmpDir, // add temp class path
            "-D", "display-details",
            "--no-output", // prevent generation
        ];

        proto.onCompletion = function(params, resolve, reject) {
            tempSave(params.textDocument.uri, function(doc, filePath, release) {
                var bytePos = doc.byteOffsetAt(params.position);
                var args = getBaseDisplayArgs().concat([
                    "--display", '$filePath@$bytePos'
                ]);
                haxeServer.process(args, function(data) {
                    release();
                    var xml = try Xml.parse(data).firstElement() catch (e:Dynamic) null;
                    if (xml == null)
                        return reject(0, "");
                    resolve(parseFieldCompletion(xml));
                });
            });
        };

        proto.onSignatureHelp = function(params, resolve, reject) {
            tempSave(params.textDocument.uri, function(doc, filePath, release) {
                var bytePos = doc.byteOffsetAt(params.position);
                var args = getBaseDisplayArgs().concat([
                    "--display", '$filePath@$bytePos'
                ]);
                haxeServer.process(args, function(data) {
                    release();
                    var xml = try Xml.parse(data).firstElement() catch (e:Dynamic) null;
                    if (xml == null)
                        return reject(0, "");
                    resolve({signatures: [{label: xml.firstChild().nodeValue}]});
                });
            });
        };

        reader.listen(proto.handleMessage);
    }

    static function parseFieldCompletion(x:Xml):Array<CompletionItem> {
        var result = [];
        for (el in x.elements()) {
            var kind = fieldKindToCompletionItemKind(el.get("k"));
            var type = null, doc = null;
            for (child in el.elements()) {
                switch (child.nodeName) {
                    case "t": type = child.firstChild().nodeValue;
                    case "d": doc = child.firstChild().nodeValue;
                }
            }
            var item:CompletionItem = {label: el.get("n")};
            if (doc != null) item.documentation = doc;
            if (kind != null) item.kind = kind;
            if (type != null) item.detail = formatType(type, kind);
            result.push(item);
        }
        return result;
    }

    static function formatType(type:String, kind:CompletionItemKind):String {
        return type;
    }

    static function fieldKindToCompletionItemKind(kind:String):CompletionItemKind {
        return switch (kind) {
            case "var": Field;
            case "method": Method;
            case "type": Class;
            case "package": File;
            default: null;
        }
    }

    static function deleteRec(path:String) {
        if (FileSystem.isDirectory(path)) {
            for (file in FileSystem.readDirectory(path))
                deleteRec(path + "/" + file);
            FileSystem.deleteDirectory(path);
        } else {
            FileSystem.deleteFile(path);
        }
    }

    // extracted from vscode sources
    static function uriToFsPath(uri:String):String {
        if (!uriRe.match(uri))
            throw 'Invalid uri: $uri';

        inline function m(i) {
            var m = uriRe.matched(i);
            return if (m != null) m else "";
        }
        var scheme = m(2);
        var authority = decodeURIComponent(m(4));
        var path = decodeURIComponent(m(5));
        var query = decodeURIComponent(m(7));
        var fragment = decodeURIComponent(m(9));

        if (authority.length > 0 && scheme == 'file')
            return '//$authority$path';
        else if (driveLetterPathRe.match(path))
            return path.charAt(1).toLowerCase() + path.substr(2);
        else
            return path;
    }
    static var driveLetterPathRe = ~/^\/[a-zA-z]:/;
    static var uriRe = ~/^(([^:\/?#]+?):)?(\/\/([^\/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?/;
    @:extern static inline function decodeURIComponent(s:String):String return untyped __js__("decodeURIComponent({0})", s);
}

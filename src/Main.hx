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
import vscode.BasicTypes;
import vscode.ProtocolTypes;
import sys.FileSystem;
using StringTools;
import Uri.*;
import SignatureHelper.prepareSignature;
import FsUtils.*;

class Main {
    static function main() {
        var reader = new MessageReader(process.stdin);
        var writer = new MessageWriter(process.stdout);

        var proto = new vscode.Protocol(writer.write);
        setupTrace(proto);

        var rootPath;
        var hxmlFile;
        var haxeServer = new HaxeServer();

        var docs = new TextDocuments();
        docs.listen(proto);

        proto.onInitialize = function(params, cancelToken, resolve, reject) {
            rootPath = params.rootPath;
            proto.sendShowMessage({type: Info, message: "Haxe language server started"});

            resolve({
                capabilities: {
                    textDocumentSync: Full,
                    completionProvider: {
                        triggerCharacters: ["."]
                    },
                    signatureHelpProvider: {
                        triggerCharacters: ["("]
                    },
                    definitionProvider: true,
                    hoverProvider: true,
                    referencesProvider: true,
                }
            });
        };

        proto.onShutdown = function(cancelToken, resolve, reject) {
            haxeServer.stop();
            resolve();
        }

        proto.onDidChangeConfiguration = function(config) {
            hxmlFile = (config.settings.haxe.buildFile : String);
            haxeServer.start(6000);
        };

        inline function getBaseDisplayArgs() return [
            "--cwd", rootPath, // change cwd to workspace root
            hxmlFile, // call completion file
            "-D", "display-details",
            "--no-output", // prevent generation
        ];

        proto.onCompletion = function(params, cancelToken, resolve, reject) {
            var doc = docs.get(params.textDocument.uri);
            var filePath = uriToFsPath(params.textDocument.uri);
            var offset = doc.offsetAt(params.position);
            var toplevel = if (offset == 0) true else doc.content.charCodeAt(offset - 1) != ".".code;
            var bytePos = doc.offsetToByteOffset(offset);
            var args = getBaseDisplayArgs().concat([
                "--display", '$filePath@$bytePos' + (if (toplevel) "@toplevel" else "")
            ]);
            haxeServer.process(args, cancelToken, doc.content, function(data) {
                if (cancelToken.canceled)
                    return;

                var xml = try Xml.parse(data).firstElement() catch (e:Dynamic) null;
                if (xml == null)
                    return reject(0, "");
                var items = if (toplevel) parseToplevelCompletion(xml) else parseFieldCompletion(xml);
                resolve(items);
            });
        };

        proto.onSignatureHelp = function(params, cancelToken, resolve, reject) {
            var doc = docs.get(params.textDocument.uri);
            var filePath = uriToFsPath(params.textDocument.uri);
            var bytePos = doc.byteOffsetAt(params.position);
            var args = getBaseDisplayArgs().concat([
                "--display", '$filePath@$bytePos'
            ]);
            haxeServer.process(args, cancelToken, doc.content, function(data) {
                if (cancelToken.canceled)
                    return;

                var xml = try Xml.parse(data).firstElement() catch (e:Dynamic) null;
                if (xml == null)
                    return reject(0, "");
                resolve({signatures: [{label: xml.firstChild().nodeValue}]});
            });
        };

        proto.onGotoDefinition = function(params, cancelToken, resolve, reject) {
            var doc = docs.get(params.textDocument.uri);
            var filePath = uriToFsPath(params.textDocument.uri);
            var bytePos = doc.byteOffsetAt(params.position);
            var args = getBaseDisplayArgs().concat([
                "--display", '$filePath@$bytePos@position'
            ]);
            haxeServer.process(args, cancelToken, doc.content, function(data) {
                if (cancelToken.canceled)
                    return;

                var xml = try Xml.parse(data).firstElement() catch (e:Dynamic) null;
                if (xml == null)
                    return reject(0, "");

                var positions = [for (el in xml.elements()) el.firstChild().nodeValue];
                if (positions.length == 0)
                    return reject(0, "no info");

                var results = [];
                for (p in positions) {
                    var pos = HaxePosition.parse(p);
                    if (pos == null) {
                        trace("Got invalid position: " + p);
                        continue;
                    }
                    results.push({
                        uri: fsPathToUri(getProperFileNameCase(pos.file)),
                        range: pos.toRange(),
                    });
                }

                switch (results.length) {
                    case 0: reject(0, "no info");
                    case 1: resolve(results[0]);
                    default: resolve(results);
                }
            });
        };

        proto.onHover = function(params, cancelToken, resolve, reject) {
            var doc = docs.get(params.textDocument.uri);
            var filePath = uriToFsPath(params.textDocument.uri);
            var bytePos = doc.byteOffsetAt(params.position);
            var args = getBaseDisplayArgs().concat([
                "--display", '$filePath@$bytePos@type'
            ]);
            haxeServer.process(args, cancelToken, doc.content, function(data) {
                if (cancelToken.canceled)
                    return;

                var xml = try Xml.parse(data).firstElement() catch (e:Dynamic) null;
                if (xml == null)
                    return reject(0, "");
                var type = xml.firstChild().nodeValue;
                resolve({contents: type});
            });
        };

        proto.onFindReferences = function(params, cancelToken, resolve, reject) {
            var doc = docs.get(params.textDocument.uri);
            var filePath = uriToFsPath(params.textDocument.uri);
            var bytePos = doc.byteOffsetAt(params.position);
            var args = getBaseDisplayArgs().concat([
                "--display", '$filePath@$bytePos@usage'
            ]);
            haxeServer.process(args, cancelToken, doc.content, function(data) {
                if (cancelToken.canceled)
                    return;

                var xml = try Xml.parse(data).firstElement() catch (e:Dynamic) null;
                if (xml == null)
                    return reject(0, "");

                var positions = [for (el in xml.elements()) el.firstChild().nodeValue];
                if (positions.length == 0)
                    return reject(0, "no info");

                var results = [];
                for (p in positions) {
                    var pos = HaxePosition.parse(p);
                    if (pos == null) {
                        trace("Got invalid position: " + p);
                        continue;
                    }
                    results.push({
                        uri: fsPathToUri(getProperFileNameCase(pos.file)),
                        range: pos.toRange(),
                    });
                }

                if (results.length == 0)
                    reject(0, "no info");
                else
                    resolve(results);
            });
        }

        reader.listen(proto.handleMessage);
    }

    static function setupTrace(protocol:vscode.Protocol) {
        haxe.Log.trace = function(v, ?i) {
            var r = [Std.string(v)];
            if (i != null && i.customParams != null) {
                for (v in i.customParams)
                    r.push(Std.string(v));
            }
            protocol.sendLogMessage({type: Log, message: r.join(" ")});
        }
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
            var name = el.get("n");
            var item:CompletionItem = {label: name};
            if (doc != null) item.documentation = doc;
            if (kind != null) item.kind = kind;
            if (type != null) item.detail = formatType(type, name, kind);
            result.push(item);
        }
        return result;
    }

    static function parseToplevelCompletion(x:Xml):Array<CompletionItem> {
        var result = [];
        for (el in x.elements()) {
            var kind = el.get("k");
            var type = el.get("t");
            var name = el.firstChild().nodeValue;

            var item:CompletionItem = {label: name};

            var displayKind = toplevelKindToCompletionItemKind(kind);
            if (displayKind != null) item.kind = displayKind;

            var fullName = name;
            if (kind == "global")
                fullName = el.get("p") + "." + name;
            else if (kind == "type")
                fullName = el.get("p");

            if (type != null || fullName != name) {
                var parts = [];
                if (fullName != name)
                    parts.push('($fullName)');
                if (type != null)
                    parts.push(type); // todo format functions?
                item.detail = parts.join(" ");
            }

            result.push(item);
        }
        return result;
    }

    static function formatType(type:String, name:String, kind:CompletionItemKind):String {
        return switch (kind) {
            case Method: name + prepareSignature(type);
            default: type;
        }
    }

    static function toplevelKindToCompletionItemKind(kind:String):CompletionItemKind {
        return switch (kind) {
            case "local": Variable;
            case "member": Field;
            case "static": Class;
            case "enum": Enum;
            case "global": Variable;
            case "type": Class;
            case "package": Module;
            default: trace("unknown toplevel item kind: " + kind); null;
        }
    }

    static function fieldKindToCompletionItemKind(kind:String):CompletionItemKind {
        return switch (kind) {
            case "var": Field;
            case "method": Method;
            case "type": Class;
            case "package": Module;
            default: trace("unknown field item kind: " + kind); null;
        }
    }
}

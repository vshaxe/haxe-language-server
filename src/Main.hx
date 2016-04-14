import js.Node.process;
import js.node.Path;
import js.node.Url;
import jsonrpc.node.MessageReader;
import jsonrpc.node.MessageWriter;
import sys.FileSystem;
using StringTools;

class HaxeContext {
    public function new() {
    }

    public function setup(directory:String, hxmlFile:String) {

    }
}

class Main {
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

        var context = new HaxeContext();
        var rootPath, tmpDir;

        proto.onInitialize = function(params, resolve, reject) {
            rootPath = params.rootPath;

            tmpDir = Path.join(rootPath, "tmp");
            deleteRec(tmpDir);

            resolve({
                capabilities: {
                    textDocumentSync: Full,
                    completionProvider: {
                        triggerCharacters: ["."]
                    }
                }
            });
        };

        proto.onDidChangeConfiguration = function(config) {
            context.setup(rootPath, config.settings.haxe.buildFile);
        };

        proto.onDidOpenTextDocument = function(params) {
            var filePath = uriToFsPath(params.textDocument.uri);
            var relativePath = Path.relative(rootPath, filePath);
            if (relativePath.startsWith("..")) return;
            var tmpPath = Path.join(tmpDir, relativePath);
            sys.FileSystem.createDirectory(Path.dirname(tmpPath));
            sys.io.File.saveContent(tmpPath, params.textDocument.text);
        };

        proto.onDidChangeTextDocument = function(params) {
            var filePath = uriToFsPath(params.textDocument.uri);
            var relativePath = Path.relative(rootPath, filePath);
            if (relativePath.startsWith("..")) return;
            var tmpPath = Path.join(tmpDir, relativePath);
            sys.io.File.saveContent(tmpPath, params.contentChanges[0].text);
        };

        proto.onDidCloseTextDocument = function(params) {
            var filePath = uriToFsPath(params.textDocument.uri);
            var relativePath = Path.relative(rootPath, filePath);
            if (relativePath.startsWith("..")) return;
            var tmpPath = Path.join(tmpDir, relativePath);
            if (FileSystem.exists(tmpPath))
                FileSystem.deleteFile(tmpPath);
        };

        proto.onCompletion = function(params, resolve, reject) {
            resolve([{label: "foo"}, {label: "bar"}]);
        };

        reader.listen(proto.handleMessage);
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

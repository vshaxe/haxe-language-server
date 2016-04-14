import js.Node.process;
import jsonrpc.node.MessageReader;
import jsonrpc.node.MessageWriter;

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
        var rootPath;

        proto.onInitialize = function(params, resolve, reject) {
            rootPath = params.rootPath;
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
            trace("open", params.textDocument.uri);
        };

        proto.onDidChangeTextDocument = function(params) {
            trace("change", params.textDocument.uri);
        };

        proto.onDidCloseTextDocument = function(params) {
            trace("close", params.textDocument.uri);
        };

        proto.onDidSaveTextDocument = function(params) {
            trace("save", params.textDocument.uri);
        };

        proto.onCompletion = function(params, resolve, reject) {
            resolve([{label: "foo"}, {label: "bar"}]);
        };

        reader.listen(proto.handleMessage);
    }
}

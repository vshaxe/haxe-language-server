import js.Node.process;
import jsonrpc.node.MessageReader;
import jsonrpc.node.MessageWriter;

class Main {
    static function main() {
        var reader = new MessageReader(process.stdin);
        var writer = new MessageWriter(process.stdout);

        var proto = new vscode.Protocol(writer.write);
        setupTrace(proto);

        var context = new Context(proto);

        proto.onInitialize = function(params, cancelToken, resolve, reject) {
            context.workspacePath = params.rootPath;
            resolve({
                capabilities: {
                    textDocumentSync: TextDocuments.syncKind,
                    completionProvider: {
                        triggerCharacters: ["."]
                    },
                    signatureHelpProvider: {
                        triggerCharacters: ["("]
                    },
                    definitionProvider: true,
                    hoverProvider: true,
                    referencesProvider: true,
                    documentSymbolProvider: true,
                }
            });
        };

        proto.onShutdown = function(cancelToken, resolve, reject) {
            context.shutdown();
            resolve();
        }

        proto.onDidChangeConfiguration = function(config) {
            context.setConfig(config.settings.haxe);
        };

        new features.CompletionFeature(context);
        new features.HoverFeature(context);
        new features.SignatureHelpFeature(context);
        new features.GotoDefinitionFeature(context);
        new features.FindReferencesFeature(context);
        new features.DocumentSymbolsFeature(context);

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
}

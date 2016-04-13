import jsonrpc.JsonRpc;
import jsonrpc.node.MessageReader;
import jsonrpc.node.MessageWriter;
import vscode.ProtocolTypes;

class Main {
    static function main() {
        new MessageWriter(js.node.Fs.createWriteStream("input")).write(JsonRpc.request(1, MethodName.Initialize, ({
            processId: -1,
            rootPath: null,
            capabilities: {},
        } : InitializeParams)));

        var reader = new MessageReader(js.node.Fs.createReadStream("input"));
        var writer = new MessageWriter(js.Node.process.stdout);

        var proto = new vscode.Protocol(writer.write);

        proto.onInitialize = function(params, resolve, reject) {
            resolve({
                capabilities: {
                    completionProvider: {
                        resolveProvider: true,
                        triggerCharacters: [".", "("]
                    }
                }
            });
        };

        proto.onCompletion = function(params, resolve, reject) {
            proto.sendShowMessage({type: Info, message: "Hello"});
            resolve([{label: "foo"}, {label: "bar"}]);
        };

        proto.onCompletionItemResolve = function(item, resolve, reject) {
            resolve(item);
        };

        reader.listen(proto.handleMessage);
    }
}

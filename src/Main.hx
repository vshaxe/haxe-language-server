import JsonRpc;
import Protocol;
import JsonRpcConnection;

class Main {
    static function main() {
        new StreamMessageWriter(js.node.Fs.createWriteStream("input")).write(JsonRpc.request(1, Protocol.Method.Initialize, ({
            processId: -1,
            rootPath: null,
            capabilities: {},
        } : InitializeParams)));

        var reader = new StreamMessageReader(js.node.Fs.createReadStream("input"));
        var writer = new StreamMessageWriter(js.Node.process.stdout);

        var proto = new Protocol();

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

        proto.sendMessage = writer.write;
        reader.listen(proto.handleMessage);
    }
}

import JsonRpc;
import Protocol;

class Main {
    static function main() {
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

        proto.sendMessage = function(message) {
            trace("OUT MESSAGE: " + message);
        }

        proto.handleMessage(({
            jsonrpc: "2.0",
            method: Protocol.Method.Completion,
            id: 1,
        } : RequestMessage));
    }
}

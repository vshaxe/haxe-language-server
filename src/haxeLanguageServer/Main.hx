package haxeLanguageServer;

import js.Node.process;
import jsonrpc.node.MessageReader;
import jsonrpc.node.MessageWriter;
import haxeLanguageServer.vscodeProtocol.Protocol;

class Main {
    static function main() {
        var reader = new MessageReader(process.stdin);
        var writer = new MessageWriter(process.stdout);
        var protocol = new Protocol(writer.write);
        setupTrace(protocol);
        new Context(protocol);
        reader.listen(protocol.handleMessage);
    }

    static function setupTrace(protocol:Protocol) {
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

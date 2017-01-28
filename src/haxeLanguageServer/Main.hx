package haxeLanguageServer;

import js.Node.process;
import jsonrpc.node.MessageReader;
import jsonrpc.node.MessageWriter;
import jsonrpc.Protocol;

class Main {
    static function main() {
        var reader = new MessageReader(process.stdin);
        var writer = new MessageWriter(process.stdout);
        var protocol = new Protocol(writer.write);
        protocol.logError = function(message) protocol.sendNotification(Methods.LogMessage, {type: Warning, message: message});
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
            protocol.sendNotification(Methods.LogMessage, {type: Log, message: r.join(" ")});
        }
    }
}

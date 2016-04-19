package vscode;

@:build(vscode.ProtocolMacro.build())
class Protocol extends jsonrpc.Protocol {
    override function logError(message:String) {
        sendShowMessage({type: Error, message: message});
    }
}

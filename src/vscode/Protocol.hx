package vscode;

@:build(vscode.ProtocolMacro.build())
class Protocol extends jsonrpc.Protocol {
    override function logError(message:String) {
        sendLogMessage({type: Error, message: message});
    }
}

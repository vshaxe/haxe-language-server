package vscodeProtocol;

@:build(vscodeProtocol.ProtocolMacro.build())
class Protocol extends jsonrpc.Protocol {
    override function logError(message:String) {
        sendLogMessage({type: Warning, message: message});
    }
}

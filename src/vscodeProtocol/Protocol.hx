package vscodeProtocol;

@:build(jsonrpc.ProtocolMacro.build("vscodeProtocol.Types.MethodNames"))
class Protocol extends jsonrpc.Protocol {
    override function logError(message:String) {
        sendLogMessage({type: Warning, message: message});
    }
}

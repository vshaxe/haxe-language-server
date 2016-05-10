package haxeLanguageServer.vscodeProtocol;

@:build(jsonrpc.ProtocolMacro.build("haxeLanguageServer.vscodeProtocol.Types.MethodNames"))
class Protocol extends jsonrpc.Protocol {
    override function logError(message:String) {
        sendLogMessage({type: Warning, message: message});
    }
}

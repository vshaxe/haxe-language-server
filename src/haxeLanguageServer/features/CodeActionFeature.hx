package haxeLanguageServer.features;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import vscodeProtocol.Types;

class CodeActionFeature {
    var context:Context;
    var diagnostics:DiagnosticsManager;

    public function new(context:Context, diagnostics:DiagnosticsManager) {
        this.context = context;
        this.diagnostics = diagnostics;
        context.protocol.onCodeAction = onCodeAction;
    }

    function onCodeAction(params:CodeActionParams, token:CancellationToken, resolve:Array<Command>->Void, reject:ResponseError<NoData>->Void) {
        var result:Array<Command> = [];
        diagnostics.addCodeActions(params, result);
        resolve(result);
    }
}

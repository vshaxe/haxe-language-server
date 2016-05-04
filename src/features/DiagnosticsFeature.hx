package features;

import vscodeProtocol.ProtocolTypes;
import vscodeProtocol.BasicTypes;
import jsonrpc.Protocol;

@:enum abstract DiagnosticKind(Int) from Int to Int {
    var DKUnusedImport = 0;

    public function getMessage() {
        return switch ((this : DiagnosticKind)) {
            case DKUnusedImport: "Unused import";
        }
    }
}

typedef HaxeDiagnostics = {
    var kind:DiagnosticKind;
    var range:Range;
}

class DiagnosticsFeature extends Feature {

    public function new(context:Context) {
        super(context);
        context.protocol.onCodeAction = onCodeAction;
    }

    public function getDiagnostics(uri:String) {
        var doc = context.documents.get(uri);
        function processReply(s:String) {
            var data:Array<HaxeDiagnostics> =
                try haxe.Json.parse(s)
                catch (e:Dynamic) {
                    trace("Error parsing diagnostics response: " + e);
                    return;
                }

            var diagnostics:Array<Diagnostic> = data.map(function (diag) return {
                range: doc.byteRangeToRange(diag.range),
                source: "haxe",
                code: (diag.kind : Int),
                severity: Warning,
                message: diag.kind.getMessage()
            });

            context.protocol.sendPublishDiagnostics({uri: uri, diagnostics: diagnostics});
        }
        function processError(error:String) {
            context.protocol.sendLogMessage({type: Error, message: error});
        }
        callDisplay(["--display", doc.fsPath + "@0@diagnostics"], null, new CancellationToken(), processReply, processError);
    }

    function onCodeAction(params:CodeActionParams, token:CancellationToken, resolve:Array<Command> -> Void, _) {
        var ret:Array<Command> = [];
        for (d in params.context.diagnostics) {
            switch ((cast d.code : DiagnosticKind)) {
                case DKUnusedImport:
                    ret.push({
                        title: "Remove import",
                        command: "haxe.applyFixes",
                        arguments: [params.textDocument.uri, 0 /*TODO*/, [{range: d.range, newText: ""}]]
                    });
            }
        }
        resolve(ret);
    }
}
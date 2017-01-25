package haxeLanguageServer.features;

import haxeLanguageServer.helper.TypeHelper;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types;

class SignatureHelpFeature {
    var context:Context;

    public function new(context) {
        this.context = context;
        context.protocol.onRequest(Methods.SignatureHelp, onSignatureHelp);
    }

    function onSignatureHelp(params:TextDocumentPositionParams, token:CancellationToken, resolve:SignatureHelp->Void, reject:ResponseError<NoData>->Void) {
        var doc = context.documents.get(params.textDocument.uri);
        var bytePos = doc.offsetToByteOffset(doc.offsetAt(params.position));
        var args = ["--display", '${doc.fsPath}@$bytePos@signature'];
        context.callDisplay(args, doc.content, token, function(data) {
            if (token.canceled)
                return;

            var help:SignatureHelp = haxe.Json.parse(data);
            context.diagnostics.clearAdditionalDiagnostics();
            provideFunctionGeneration(params, help);
            resolve(help);
        }, function(error) reject(ResponseError.internalError(error)));
    }

    function provideFunctionGeneration(params:TextDocumentPositionParams, help:SignatureHelp) {
        var signature = help.signatures[help.activeSignature].parameters[help.activeParameter].label;
        var currentType = TypeHelper.parseFunctionArgumentType(signature);
        switch (currentType) {
            case DTFunction(args, ret):
                var generatedCode = TypeHelper.printFunctionDeclaration(args) + " ";
                var range = { start: params.position, end: params.position};
                var title = "Generate inline function";
                context.diagnostics.addAdditionalDiagnostic(params.textDocument.uri, {
                    code: -1,
                    range: range,
                    severity: DiagnosticSeverity.Hint,
                    source: "haxe",
                    message: title
                }, {
                    title: title,
                    command: "haxe.applyFixes",
                    arguments: [params.textDocument.uri, 0, [{range: range, newText: generatedCode}]]
                });
            case _:
        }
    }
}

package haxeLanguageServer.features;

import haxeLanguageServer.helper.TypeHelper;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types;

class SignatureHelpFeature {
    var context:Context;
    var lastResponse:{help: SignatureHelp, params: TextDocumentPositionParams};

    public function new(context:Context) {
        this.context = context;
        context.codeActions.registerContributor(provideFunctionGeneration);
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
            resolve(help);
            lastResponse = {help: help, params: params};
        }, function(error) reject(ResponseError.internalError(error)));
    }

    function provideFunctionGeneration(params:CodeActionParams):Array<Command> {
        if (lastResponse == null || lastResponse.params.textDocument.uri != params.textDocument.uri) return [];

        var help = lastResponse.help;
        var activeParam = help.signatures[help.activeSignature].parameters[help.activeParameter];
        if (activeParam == null) return [];
        
        var position = lastResponse.params.position;
        var currentType = TypeHelper.parseFunctionArgumentType(activeParam.label);
        switch (currentType) {
            case DTFunction(args, ret):
                var generatedCode = TypeHelper.printFunctionDeclaration(args, ret, context.config.codeGeneration.functions.anonymous) + " ";
                return [{
                    title: "Generate anonymous function",
                    command: "haxe.applyFixes",
                    arguments: [params.textDocument.uri, 0, [{range: position.toRange(), newText: generatedCode}]]
                }];
            case _:
                return [];
        }
    }
}

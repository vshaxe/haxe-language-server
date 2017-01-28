package haxeLanguageServer.features;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

typedef CurrentSignature = {
    var help(default, never):SignatureHelp;
    var params(default, never):TextDocumentPositionParams; 
}

class SignatureHelpFeature {
    public var currentSignature(default, null):CurrentSignature;
    var context:Context;

    public function new(context:Context) {
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
            resolve(help);
            currentSignature = {help: help, params: params};
        }, function(error) reject(ResponseError.internalError(error)));
    }
}

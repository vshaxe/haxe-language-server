package haxeLanguageServer.features;

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
            resolve(haxe.Json.parse(data));
        }, function(error) reject(ResponseError.internalError(error)));
    }
}

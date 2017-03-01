package haxeLanguageServer.features;

import haxeLanguageServer.helper.DocHelper;
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
        context.callDisplay(args, doc.content, token, function(r) {
            switch (r) {
                case DCancelled:
                    resolve(null);
                case DResult(data):
                    var help:SignatureHelp = haxe.Json.parse(data);
                    for (signature in help.signatures)
                        signature.documentation = DocHelper.extractText(signature.documentation);
                    resolve(help);

                    if (currentSignature != null) {
                        var oldDoc = context.documents.get(currentSignature.params.textDocument.uri);
                        oldDoc.removeUpdateListener(onUpdateTextDocument);
                    }
                    currentSignature = {help: help, params: params};
                    doc.addUpdateListener(onUpdateTextDocument);
            }
        }, function(error) reject(ResponseError.internalError(error)));
    }

    function onUpdateTextDocument(doc:TextDocument, events:Array<TextDocumentContentChangeEvent>, version:Int) {
        // if there's any non-whitespace changes, consider us not to be in the signature anymore
        // - otherwise, code actions might generate incorrect code
        inline function hasNonWhitespace(s:String)
            return s.trim().length > 0;

        for (event in events) {
            if (event.range == null)
                continue;

            if (event.range.start.isAfterOrEqual(event.range.end)) {
                if (hasNonWhitespace(event.text)) {
                    currentSignature = null;
                    break;
                }
            } else { // removing text
                var removedText = doc.getText(event.range);
                if (hasNonWhitespace(removedText)) {
                    currentSignature = null;
                    break;
                }
            }
        }
    }
}

package haxeLanguageServer.features;

import haxe.Timer;
import tokentreeformatter.Formatter;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

class DocumentFormattingFeature {
    final context:Context;

    public function new(context) {
        this.context = context;
        context.protocol.onRequest(Methods.DocumentFormatting, onDocumentFormatting);
    }

    function onDocumentFormatting(params:DocumentFormattingParams, token:CancellationToken, resolve:Array<TextEdit>->Void, reject:ResponseError<NoData>->Void) {
        var stamp = Timer.stamp();

        var doc = context.documents.get(params.textDocument.uri);
        var formatter = new Formatter();
        try {
            var result = formatter.formatFile({
                    name: doc.uri.toFsPath().toString(),
                    content: doc.bytes
                }, {
                    tokens: doc.tokens,
                    tokenTree: doc.tokenTree
                }
            );
            switch (result) {
                case Success(formattedCode):
                    var fullRange = {
                        start: {line: 0, character: 0},
                        end: {line: doc.lineCount - 1, character: doc.lineAt(doc.lineCount - 1).length}
                    }
                    trace("formatting took " + ((Timer.stamp() - stamp) * 1000) + "ms");
                    resolve([{range: fullRange, newText: formattedCode}]);
                case Failure(errorMessage):
                    reject(ResponseError.internalError(errorMessage));
                case Disabled:
                    reject(ResponseError.internalError("Formatting is disabled for this file"));
            }
        } catch (e:Any) {
            reject(ResponseError.internalError(e));
        }
    }
}

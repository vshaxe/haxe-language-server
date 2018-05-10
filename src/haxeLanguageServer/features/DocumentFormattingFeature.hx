package haxeLanguageServer.features;

import haxeFormatter.Formatter;
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
        var doc = context.documents.get(params.textDocument.uri);
        switch (Formatter.formatSource(doc.content, File, context.config.format)) {
            case Success(s):
                var fullRange = {
                    start: {line: 0, character: 0},
                    end: {line: doc.lineCount - 1, character: doc.lineAt(doc.lineCount - 1).length}
                }
                resolve([{range: fullRange, newText: s}]);
            case Failure(reason):
                reject(ResponseError.internalError(reason));
        }
    }
}

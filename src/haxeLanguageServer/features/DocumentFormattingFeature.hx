package haxeLanguageServer.features;

import byte.ByteData;
import tokentreeformatter.config.Config;
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
        var doc = context.documents.get(params.textDocument.uri);
        var formatter = new Formatter();
        try {
            var formattedFile = formatter.formatFile({
                    name: doc.uri.toFsPath().toString(),
                    content: ByteData.ofString(doc.content)
                }
            );
            if (formattedFile == null) {
                resolve([]);
                return;
            }
            var fullRange = {
                start: {line: 0, character: 0},
                end: {line: doc.lineCount - 1, character: doc.lineAt(doc.lineCount - 1).length}
            }
            resolve([{range: fullRange, newText: formattedFile}]);
        } catch (e:Any) {
            trace(e);
        }
    }
}

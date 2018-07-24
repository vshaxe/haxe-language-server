package haxeLanguageServer.features;

import haxeLanguageServer.tokentree.DocumentSymbolsResolver;
import haxe.extern.EitherType;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

class DocumentSymbolsFeature {
    final context:Context;

    public function new(context) {
        this.context = context;
        context.protocol.onRequest(Methods.DocumentSymbols, onDocumentSymbols);
    }

    function onDocumentSymbols(params:DocumentSymbolParams, token:CancellationToken, resolve:Array<EitherType<SymbolInformation,DocumentSymbol>>->Void, reject:ResponseError<NoData>->Void) {
        var onResolve = context.startTimer(Methods.DocumentSymbols);
        var doc = context.documents.get(params.textDocument.uri);
        var symbols = new DocumentSymbolsResolver(doc).resolve();
        resolve(symbols);
        onResolve(symbols);
    }
}

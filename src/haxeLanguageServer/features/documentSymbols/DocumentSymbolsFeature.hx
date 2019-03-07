package haxeLanguageServer.features.documentSymbols;

import haxe.extern.EitherType;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

using Lambda;

class DocumentSymbolsFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.languageServerProtocol.onRequest(Methods.DocumentSymbols, onDocumentSymbols);
	}

	function onDocumentSymbols(params:DocumentSymbolParams, token:CancellationToken, resolve:Array<EitherType<SymbolInformation, DocumentSymbol>>->Void,
			reject:ResponseError<NoData>->Void) {
		var onResolve = context.startTimer(Methods.DocumentSymbols);
		var doc = context.documents.get(params.textDocument.uri);
		if (doc.tokens == null) {
			return reject.noTokens();
		}
		var symbols = new DocumentSymbolsResolver(doc).resolve();
		resolve(symbols);
		onResolve(symbols, countSymbols(symbols) + " symbols");
	}

	function countSymbols(symbols:Array<DocumentSymbol>):Int {
		return if (symbols == null) {
			0;
		} else {
			symbols.length + symbols.map(symbol -> countSymbols(symbol.children)).fold((a, b) -> a + b, 0);
		}
	}
}

package haxeLanguageServer.features.haxe.documentSymbols;

import haxe.extern.EitherType;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

using Lambda;

class DocumentSymbolsFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.languageServerProtocol.onRequest(DocumentSymbolRequest.type, onDocumentSymbols);
	}

	function onDocumentSymbols(params:DocumentSymbolParams, token:CancellationToken, resolve:Array<EitherType<SymbolInformation, DocumentSymbol>>->Void,
			reject:ResponseError<NoData>->Void) {
		var onResolve = context.startTimer("haxe/documentSymbol");
		var uri = params.textDocument.uri;
		var doc = context.documents.getHaxe(uri);
		if (doc == null) {
			return reject.noFittingDocument(uri);
		}
		if (doc.tokens == null) {
			return reject.noTokens();
		}
		var symbols = new DocumentSymbolsResolver(doc).resolve();
		resolve(symbols);
		onResolve(null, countSymbols(symbols) + " symbols");
	}

	function countSymbols(symbols:Array<DocumentSymbol>):Int {
		return if (symbols == null) {
			0;
		} else {
			symbols.length + symbols.map(symbol -> countSymbols(symbol.children)).fold((a, b) -> a + b, 0);
		}
	}
}

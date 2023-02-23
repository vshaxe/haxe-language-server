package haxeLanguageServer.features.haxe.foldingRange;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.FoldingRange;
import languageServerProtocol.protocol.FoldingRange;

class FoldingRangeFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.languageServerProtocol.onRequest(FoldingRangeRequest.type, onFoldingRange);
	}

	function onFoldingRange(params:FoldingRangeParams, token:CancellationToken, resolve:Array<FoldingRange>->Void, reject:ResponseError<NoData>->Void) {
		final onResolve = context.startTimer("textDocument/foldingRange");
		final uri = params.textDocument.uri;
		final doc = context.documents.getHaxe(uri);
		if (doc == null) {
			return reject.noFittingDocument(uri);
		}
		if (doc.tokens == null) {
			return reject.noTokens();
		}
		final ranges = new FoldingRangeResolver(doc, context.capabilities.textDocument).resolve();
		resolve(ranges);
		onResolve(null, ranges.length + " ranges");
	}
}

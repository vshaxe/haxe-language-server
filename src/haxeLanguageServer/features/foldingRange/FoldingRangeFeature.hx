package haxeLanguageServer.features.foldingRange;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.protocol.FoldingRange;

class FoldingRangeFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.languageServerProtocol.onRequest(FoldingRangeRequest.type, onFoldingRange);
	}

	function onFoldingRange(params:FoldingRangeParams, token:CancellationToken, resolve:Array<FoldingRange>->Void, reject:ResponseError<NoData>->Void) {
		var onResolve = context.startTimer("haxe/foldingRange");
		var doc = context.documents.get(params.textDocument.uri);
		if (doc.tokens == null) {
			return reject.noTokens();
		}
		var ranges = new FoldingRangeResolver(doc, context.capabilities.textDocument).resolve();
		resolve(ranges);
		onResolve(null, ranges.length + " ranges");
	}
}

package haxeLanguageServer.features.foldingRange;

import languageServerProtocol.protocol.FoldingRange;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import jsonrpc.CancellationToken;

class FoldingRangeFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.protocol.onRequest(FoldingRangeMethods.FoldingRange, onFoldingRange);
	}

	function onFoldingRange(params:FoldingRangeParams, token:CancellationToken, resolve:Array<FoldingRange>->Void, reject:ResponseError<NoData>->Void) {
		var onResolve = context.startTimer(FoldingRangeMethods.FoldingRange);
		var doc = context.documents.get(params.textDocument.uri);
		var ranges = new FoldingRangeResolver(doc, context.capabilities.textDocument).resolve();
		resolve(ranges);
		onResolve(ranges);
	}
}

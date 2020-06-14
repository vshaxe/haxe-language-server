package haxeLanguageServer.features.hxml;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

class CompletionFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
	}

	public function onCompletion(params:CompletionParams, token:CancellationToken, resolve:CompletionList->Void, reject:ResponseError<NoData>->Void) {
		trace("hxml completion");
		resolve({
			isIncomplete: false,
			items: []
		});
	}
}

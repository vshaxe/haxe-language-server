package haxeLanguageServer.features.hxml;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

class HoverFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.languageServerProtocol.onRequest(HoverRequest.type, onHover);
	}

	public function onHover(params:TextDocumentPositionParams, token:CancellationToken, resolve:Null<Hover>->Void, reject:ResponseError<NoData>->Void) {
		trace("hxml hover");
		resolve(null);
	}
}
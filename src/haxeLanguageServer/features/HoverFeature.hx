package haxeLanguageServer.features;

import haxeLanguageServer.features.haxe.HoverFeature as HaxeHoverFeature;
import haxeLanguageServer.features.hxml.HoverFeature as HxmlHoverFeature;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.Hover;

class HoverFeature {
	final haxe:HaxeHoverFeature;
	final hxml:HxmlHoverFeature;

	public function new(context) {
		haxe = new HaxeHoverFeature(context);
		hxml = new HxmlHoverFeature(context);

		context.languageServerProtocol.onRequest(HoverRequest.type, onHover);
	}

	public function onHover(params:TextDocumentPositionParams, token:CancellationToken, resolve:Null<Hover>->Void, reject:ResponseError<NoData>->Void) {
		final uri = params.textDocument.uri;
		if (uri.isHaxeFile()) {
			haxe.onHover(params, token, resolve, reject);
		} else if (uri.isHxmlFile()) {
			hxml.onHover(params, token, resolve, reject);
		} else {
			reject.noFittingDocument(uri);
		}
	}
}

package haxeLanguageServer.features;

import haxeLanguageServer.features.haxe.completion.CompletionFeature as HaxeCompletionFeature;
import haxeLanguageServer.features.hxml.CompletionFeature as HxmlCompletionFeature;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

class CompletionFeature {
	final haxe:HaxeCompletionFeature;
	final hxml:HxmlCompletionFeature;

	public function new(context) {
		haxe = new HaxeCompletionFeature(context);
		hxml = new HxmlCompletionFeature(context);

		context.languageServerProtocol.onRequest(CompletionRequest.type, onCompletion);
		context.languageServerProtocol.onRequest(CompletionResolveRequest.type, onCompletionResolve);
	}

	function onCompletion(params:CompletionParams, token:CancellationToken, resolve:CompletionList->Void, reject:ResponseError<NoData>->Void) {
		final uri = params.textDocument.uri;
		if (uri.isHaxeFile()) {
			haxe.onCompletion(params, token, resolve, reject);
		} else if (uri.isHxmlFile()) {
			hxml.onCompletion(params, token, resolve, reject);
		} else {
			reject.noFittingDocument(uri);
		}
	}

	function onCompletionResolve(item:CompletionItem, token:CancellationToken, resolve:CompletionItem->Void, reject:ResponseError<NoData>->Void) {
		if (item.data != null) {
			haxe.onCompletionResolve(item, token, resolve, reject);
		} else {
			resolve(item);
		}
	}
}

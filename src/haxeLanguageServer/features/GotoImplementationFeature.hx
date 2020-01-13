package haxeLanguageServer.features;

import haxe.display.Display;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.protocol.Implementation;

class GotoImplementationFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.languageServerProtocol.onRequest(ImplementationRequest.type, onGotoImplementation);
	}

	public function onGotoImplementation(params:TextDocumentPositionParams, token:CancellationToken, resolve:Definition->Void,
			reject:ResponseError<NoData>->Void) {
		var doc = context.documents.get(params.textDocument.uri);
		if (!doc.uri.isFile()) {
			return reject.notAFile();
		}
		handleJsonRpc(params, token, resolve, reject, doc, doc.offsetAt(params.position));
	}

	function handleJsonRpc(params:TextDocumentPositionParams, token:CancellationToken, resolve:Definition->Void, reject:ResponseError<NoData>->Void,
			doc:TextDocument, offset:Int) {
		context.callHaxeMethod(DisplayMethods.GotoImplementation, {file: doc.uri.toFsPath(), contents: doc.content, offset: offset}, token, locations -> {
			resolve(locations.map(location -> {
				{
					uri: location.file.toUri(),
					range: location.range
				}
			}));
			return null;
		}, reject.handler());
	}
}

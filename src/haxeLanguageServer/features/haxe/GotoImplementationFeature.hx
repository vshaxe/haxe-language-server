package haxeLanguageServer.features.haxe;

import haxe.display.Display;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.Definition;
import languageServerProtocol.protocol.Implementation;

class GotoImplementationFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.languageServerProtocol.onRequest(ImplementationRequest.type, onGotoImplementation);
	}

	public function onGotoImplementation(params:TextDocumentPositionParams, token:CancellationToken, resolve:Definition->Void,
			reject:ResponseError<NoData>->Void) {
		final uri = params.textDocument.uri;
		final doc = context.documents.getHaxe(uri);
		if (doc == null || !uri.isFile()) {
			return reject.noFittingDocument(uri);
		}
		final offset = context.displayOffsetConverter.characterOffsetToByteOffset(doc.content, doc.offsetAt(params.position));
		handleJsonRpc(params, token, resolve, reject, doc, offset);
	}

	function handleJsonRpc(params:TextDocumentPositionParams, token:CancellationToken, resolve:Definition->Void, reject:ResponseError<NoData>->Void,
			doc:HxTextDocument, offset:Int) {
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

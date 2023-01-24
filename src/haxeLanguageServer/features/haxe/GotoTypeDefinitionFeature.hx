package haxeLanguageServer.features.haxe;

import haxe.display.Display;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.protocol.TypeDefinition;

class GotoTypeDefinitionFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.languageServerProtocol.onRequest(TypeDefinitionRequest.type, onGotoTypeDefinition);
	}

	public function onGotoTypeDefinition(params:TextDocumentPositionParams, token:CancellationToken, resolve:Definition->Void,
			reject:ResponseError<NoData>->Void) {
		final uri = params.textDocument.uri;
		final doc = context.documents.getHaxe(uri);
		if (doc == null || !uri.isFile()) {
			return reject.noFittingDocument(uri);
		}
		final offset = context.displayOffsetConverter.characterOffsetToByteOffset(doc.content, doc.offsetAt(params.position));
		context.callHaxeMethod(DisplayMethods.GotoTypeDefinition, {file: uri.toFsPath(), contents: doc.content, offset: offset}, token,
			locations -> {
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

package haxeLanguageServer.features;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import haxeLanguageServer.protocol.Display;
import haxeLanguageServer.helper.HaxePosition;

class GotoDefinitionFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.languageServerProtocol.onRequest(Methods.GotoDefinition, onGotoDefinition);
	}

	public function onGotoDefinition(params:TextDocumentPositionParams, token:CancellationToken, resolve:Definition->Void,
			reject:ResponseError<NoData>->Void) {
		var doc = context.documents.get(params.textDocument.uri);
		if (!doc.uri.isFile()) {
			return reject.notAFile();
		}
		var handle = if (context.haxeServer.supports(DisplayMethods.GotoDefinition)) handleJsonRpc else handleLegacy;
		handle(params, token, resolve, reject, doc, doc.offsetAt(params.position));
	}

	function handleJsonRpc(params:TextDocumentPositionParams, token:CancellationToken, resolve:Definition->Void, reject:ResponseError<NoData>->Void,
			doc:TextDocument, offset:Int) {
		context.callHaxeMethod(DisplayMethods.GotoDefinition, {file: context.relativePath(doc.uri.toFsPath()), contents: doc.content, offset: offset}, token,
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

	function handleLegacy(params:TextDocumentPositionParams, token:CancellationToken, resolve:Definition->Void, reject:ResponseError<NoData>->Void,
			doc:TextDocument, offset:Int) {
		var bytePos = context.displayOffsetConverter.characterOffsetToByteOffset(doc.content, offset);
		var args = ['${doc.uri.toFsPath()}@$bytePos@position'];
		context.callDisplay("@position", args, doc.content, token, function(r) {
			switch r {
				case DCancelled:
					resolve(null);
				case DResult(data):
					var xml = try Xml.parse(data).firstElement() catch (_:Any) null;
					if (xml == null)
						return reject.invalidXml(data);

					var positions = [for (el in xml.elements()) el.firstChild().nodeValue];
					if (positions.length == 0)
						resolve([]);
					var results = [];
					for (pos in positions) {
						var location = HaxePosition.parse(pos, doc, null, context
							.displayOffsetConverter); // no cache because this right now only returns one position
						if (location == null) {
							trace("Got invalid position: " + pos);
							continue;
						}
						results.push(location);
					}
					resolve(results);
			}
		}, reject.handler());
	}
}

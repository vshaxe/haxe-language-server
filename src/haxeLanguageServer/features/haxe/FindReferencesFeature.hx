package haxeLanguageServer.features.haxe;

import haxe.display.Display.DisplayMethods;
import haxeLanguageServer.helper.HaxePosition;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.Location;

class FindReferencesFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.languageServerProtocol.onRequest(ReferencesRequest.type, onFindReferences);
	}

	public function onFindReferences(params:TextDocumentPositionParams, token:CancellationToken, resolve:Null<Array<Location>>->Void,
			reject:ResponseError<NoData>->Void) {
		final uri = params.textDocument.uri;
		final doc = context.documents.getHaxe(uri);
		if (doc == null || !uri.isFile()) {
			return reject.noFittingDocument(uri);
		}
		final handle = if (context.haxeServer.supports(DisplayMethods.FindReferences)) handleJsonRpc else handleLegacy;
		final offset = context.displayOffsetConverter.characterOffsetToByteOffset(doc.content, doc.offsetAt(params.position));
		handle(params, token, resolve, reject, doc, offset);
	}

	function handleJsonRpc(params:TextDocumentPositionParams, token:CancellationToken, resolve:Null<Array<Location>>->Void,
			reject:ResponseError<NoData>->Void, doc:HxTextDocument, offset:Int) {
		context.callHaxeMethod(DisplayMethods.FindReferences, {
			file: doc.uri.toFsPath(),
			contents: doc.content,
			offset: offset,
			kind: WithBaseAndDescendants
		}, token, locations -> {
			resolve(locations.filter(location -> location != null).map(location -> {
				{
					uri: location.file.toUri(),
					range: location.range
				}
			}));
			return null;
		}, reject.handler());
	}

	function handleLegacy(params:TextDocumentPositionParams, token:CancellationToken, resolve:Null<Array<Location>>->Void, reject:ResponseError<NoData>->Void,
			doc:HxTextDocument, offset:Int) {
		final args = ['${doc.uri.toFsPath()}@$offset@usage'];
		context.callDisplay("@usage", args, doc.content, token, function(r) {
			switch r {
				case DCancelled:
					resolve(null);
				case DResult(data):
					final xml = try Xml.parse(data).firstElement() catch (_:Any) null;
					if (xml == null)
						return reject.invalidXml(data);

					final positions = [for (el in xml.elements()) el.firstChild().nodeValue];
					if (positions.length == 0)
						return resolve([]);

					final results = [];
					final haxePosCache = new Map();
					for (pos in positions) {
						final location = HaxePosition.parse(pos, doc, haxePosCache, context.displayOffsetConverter);
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

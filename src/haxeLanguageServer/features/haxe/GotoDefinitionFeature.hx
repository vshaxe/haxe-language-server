package haxeLanguageServer.features.haxe;

import haxe.display.Display;
import haxeLanguageServer.helper.HaxePosition;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.DefinitionLink;

class GotoDefinitionFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.languageServerProtocol.onRequest(DefinitionRequest.type, onGotoDefinition);
	}

	public function onGotoDefinition(params:TextDocumentPositionParams, token:CancellationToken, resolve:Array<DefinitionLink>->Void,
			reject:ResponseError<NoData>->Void) {
		final uri = params.textDocument.uri;
		final doc = context.documents.getHaxe(uri);
		if (doc == null || !uri.isFile()) {
			return reject.noFittingDocument(uri);
		}
		final handle = if (context.haxeServer.supports(DisplayMethods.GotoDefinition)) handleJsonRpc else handleLegacy;
		final offset = context.displayOffsetConverter.characterOffsetToByteOffset(doc.content, doc.offsetAt(params.position));
		handle(params, token, resolve, reject, doc, offset);
	}

	function handleJsonRpc(params:TextDocumentPositionParams, token:CancellationToken, resolve:Array<DefinitionLink>->Void,
			reject:ResponseError<NoData>->Void, doc:HxTextDocument, offset:Int) {
		context.callHaxeMethod(DisplayMethods.GotoDefinition, {
			file: doc.uri.toFsPath(),
			contents: doc.content,
			offset: offset
		}, token, function(locations) {
			resolve(locations.map(location -> {
				final document = getHaxeDocument(location.file.toUri());
				final tokens = document!.tokens;
				var previewDeclarationRange = location.range;
				if (document != null && tokens != null) {
					final targetToken = tokens!.getTokenAtOffset(document.offsetAt(location.range.start));
					final pos = targetToken!.parent!.getPos();
					if (pos != null)
						previewDeclarationRange = document.rangeAt(pos.min, pos.max);
				}

				final link:DefinitionLink = {
					targetUri: location.file.toUri(),
					targetRange: previewDeclarationRange,
					targetSelectionRange: location.range,
				};
				link;
			}));
			return null;
		}, reject.handler());
	}

	function getHaxeDocument(uri:DocumentUri):Null<HaxeDocument> {
		var document = context.documents.getHaxe(uri);
		if (document == null) {
			final path = uri.toFsPath().toString();
			if (!sys.FileSystem.exists(path))
				return null;
			final content = sys.io.File.getContent(path);
			document = new HaxeDocument(uri, "haxe", 0, content);
		}
		return document;
	}

	function handleLegacy(params:TextDocumentPositionParams, token:CancellationToken, resolve:Array<DefinitionLink>->Void, reject:ResponseError<NoData>->Void,
			doc:HxTextDocument, offset:Int) {
		final args = ['${doc.uri.toFsPath()}@$offset@position'];
		context.callDisplay("@position", args, doc.content, token, function(r) {
			switch r {
				case DCancelled:
					resolve([]);
				case DResult(data):
					final xml = try Xml.parse(data).firstElement() catch (_:Any) null;
					if (xml == null)
						return reject.invalidXml(data);

					final positions = [for (el in xml.elements()) el.firstChild().nodeValue];
					if (positions.length == 0)
						resolve([]);
					final results:Array<DefinitionLink> = [];
					for (pos in positions) {
						// no cache because this right now only returns one position
						final location = HaxePosition.parse(pos, doc, null, context.displayOffsetConverter);
						if (location == null) {
							trace("Got invalid position: " + pos);
							continue;
						}
						results.push({
							targetUri: location.uri,
							targetRange: location.range,
							targetSelectionRange: location.range
						});
					}
					resolve(results);
			}
		}, reject.handler());
	}
}

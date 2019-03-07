package haxeLanguageServer.features;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.helper.DocHelper.printCodeBlock;
import haxeLanguageServer.helper.HaxePosition;
import haxeLanguageServer.helper.TypeHelper.*;
import haxeLanguageServer.protocol.helper.DisplayPrinter;
import haxeLanguageServer.protocol.Display;

class HoverFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.languageServerProtocol.onRequest(Methods.Hover, onHover);
	}

	function onHover(params:TextDocumentPositionParams, token:CancellationToken, resolve:Hover->Void, reject:ResponseError<NoData>->Void) {
		var uri = params.textDocument.uri;
		if (!uri.isFile()) {
			return reject.notAFile();
		}
		var doc:Null<TextDocument> = context.documents.get(uri);
		if (doc == null) {
			return reject.documentNotFound(uri);
		}
		var handle = if (context.haxeServer.supports(DisplayMethods.Hover)) handleJsonRpc else handleLegacy;
		handle(params, token, resolve, reject, doc, doc.offsetAt(params.position));
	}

	function handleJsonRpc(params:TextDocumentPositionParams, token:CancellationToken, resolve:Hover->Void, reject:ResponseError<NoData>->Void,
			doc:TextDocument, offset:Int) {
		context.callHaxeMethod(DisplayMethods.Hover, {file: doc.uri.toFsPath(), contents: doc.content, offset: offset}, token, hover -> {
			resolve(createHover(printContent(hover), hover.item.getDocumentation(), hover.range));
			return null;
		}, reject.handler());
	}

	function printContent<T>(hover:HoverDisplayItemOccurence<T>):HoverContent {
		var printer = new DisplayPrinter(true, Qualified, {
			argumentTypeHints: true,
			returnTypeHint: NonVoid,
			explicitPublic: true,
			explicitPrivate: true,
			explicitNull: true
		});
		var item = hover.item;
		var concreteType = hover.item.type;
		var result:HoverContent = switch (item.kind) {
			case Type:
				{definition: printCodeBlock(printer.printEmptyTypeDefinition(hover.item.args), Haxe)}
			case Local:
				var languageId = if (item.args.origin == Argument) HaxeArgument else Haxe;
				{
					definition: printCodeBlock(printer.printLocalDefinition(hover.item.args, concreteType), languageId),
					origin: printer.printLocalOrigin(item.args.origin)
				}
			case ClassField:
				{
					definition: printCodeBlock(printer.printClassFieldDefinition(item.args, concreteType, item.kind == EnumAbstractField), Haxe),
					origin: switch (printer.printClassFieldOrigin(item.args.origin, item.kind)) {
						case Some(v): v;
						case None: null;
					}
				}
			case EnumField:
				{
					definition: printCodeBlock(printer.printEnumFieldDefinition(item.args.field, item.type), Haxe),
					origin: switch (printer.printEnumFieldOrigin(item.args.origin)) {
						case Some(v): v;
						case None: null;
					}
				}
			case Metadata:
				var name = item.args.name;
				if (name.charAt(0) != "@")
					name = "@" + name; // backward compatibility with preview 4
				{definition: printCodeBlock(name, Haxe)};
			case _:
				{definition: printCodeBlock(printer.printType(concreteType), HaxeType)};
		}

		var expected = hover.expected;
		if (expected != null && expected.name != null && expected.name.kind == FunctionArgument) {
			var argument = expected.name.name;
			if (expected.type != null) {
				var printer = new DisplayPrinter(PathPrinting.Never);
				argument += ":" + printer.printType(expected.type);
			}
			result.additionalContents = ['*for argument `$argument`*'];
		}

		return result;
	}

	function handleLegacy(params:TextDocumentPositionParams, token:CancellationToken, resolve:Hover->Void, reject:ResponseError<NoData>->Void,
			doc:TextDocument, offset:Int) {
		var bytePos = context.displayOffsetConverter.characterOffsetToByteOffset(doc.content, offset);
		var args = ['${doc.uri.toFsPath()}@$bytePos@type'];
		context.callDisplay("@type", args, doc.content, token, function(r) {
			switch (r) {
				case DCancelled:
					resolve(null);
				case DResult(data):
					var xml = try Xml.parse(data).firstElement() catch (_:Any) null;
					if (xml == null)
						return reject.invalidXml(data);

					var s = StringTools.trim(xml.firstChild().nodeValue);
					switch (xml.nodeName) {
						case "metadata":
							if (s.length == 0)
								return reject(new ResponseError(0, "No metadata information"));
							resolve({contents: s});
						case _:
							if (s.length == 0)
								return reject(new ResponseError(0, "No type information"));
							var type = switch (parseDisplayType(s)) {
								case DTFunction(args, ret):
									printFunctionType(args, ret);
								case DTValue(type):
									if (type == null) "unknown" else type;
							};
							var documentation = xml.get("d");
							var p = HaxePosition.parse(xml.get("p"), doc, null, context.displayOffsetConverter);
							var range:Null<Range> = null;
							if (p != null)
								range = p.range;
							var definition = {definition: printCodeBlock(type, HaxeType)};
							resolve(createHover(definition, documentation, range));
					}
			}
		}, reject.handler());
	}

	function createHover(content:HoverContent, ?documentation:String, ?range:Range):Hover {
		documentation = if (documentation == null) "" else "\n" + DocHelper.markdownFormat(documentation);
		if (content.origin != null) {
			documentation = '*${content.origin}*\n' + documentation;
		}
		if (content.additionalContents == null)
			content.additionalContents = [];
		var hover:Hover = {
			contents: [content.definition, documentation].concat(content.additionalContents)
		};
		if (range != null)
			hover.range = range;
		return hover;
	}
}

private typedef HoverContent = {
	definition:String,
	?origin:String,
	?additionalContents:Array<String>
}

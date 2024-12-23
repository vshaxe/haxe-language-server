package haxeLanguageServer.features.haxe;

import haxe.display.Display;
import haxeLanguageServer.helper.DocHelper.printCodeBlock;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.helper.HaxePosition;
import haxeLanguageServer.helper.TypeHelper.*;
import haxeLanguageServer.protocol.DisplayPrinter;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.Hover;
import languageServerProtocol.Types.MarkupKind;

class HoverFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
	}

	public function onHover(params:TextDocumentPositionParams, token:CancellationToken, resolve:Null<Hover>->Void, reject:ResponseError<NoData>->Void) {
		final uri = params.textDocument.uri;
		final doc:Null<HaxeDocument> = context.documents.getHaxe(uri);
		if (doc == null || !uri.isFile()) {
			return reject.noFittingDocument(uri);
		}
		final handle = if (context.haxeServer.supports(DisplayMethods.Hover)) handleJsonRpc else handleLegacy;
		final offset = context.displayOffsetConverter.characterOffsetToByteOffset(doc.content, doc.offsetAt(params.position));
		handle(params, token, resolve, reject, doc, offset);
	}

	function handleJsonRpc(params:TextDocumentPositionParams, token:CancellationToken, resolve:Null<Hover>->Void, reject:ResponseError<NoData>->Void,
			doc:HxTextDocument, offset:Int) {
		context.callHaxeMethod(DisplayMethods.Hover, {file: doc.uri.toFsPath(), contents: doc.content, offset: offset}, token, function(hover) {
			if (hover == null || hover.range == null) {
				resolve(null);
			} else {
				final range = context.displayOffsetConverter.byteRangeToCharacterRange(hover.range, doc);
				resolve(createHover(printContent(doc, hover), hover.item.getDocumentation(), range));
			}
			return null;
		}, reject.handler());
	}

	function printContent<T>(doc:HxTextDocument, hover:HoverDisplayItemOccurence<T>):HoverContent {
		final printer = new DisplayPrinter(true, Qualified, {
			argumentTypeHints: true,
			returnTypeHint: NonVoid,
			useArrowSyntax: false,
			placeOpenBraceOnNewLine: false,
			explicitPublic: true,
			explicitPrivate: true,
			explicitNull: true
		});
		final item = hover.item;
		function getType() {
			return hover.item.type.sure();
		}
		function printType():HoverContent {
			final type = printer.printType(getType());
			return {definition: printCodeBlock(type, HaxeType)};
		}
		final result:HoverContent = switch item.kind {
			case Type:
				final typeDefinition = printer.printEmptyTypeDefinition(hover.item.args);
				{definition: printCodeBlock(typeDefinition, Haxe)}
			case Local:
				final languageId = if (item.args.origin == Argument) HaxeArgument else Haxe;
				final local = printer.printLocalDefinition(hover.item.args, getType());
				{
					definition: printCodeBlock(local, languageId),
					origin: printer.printLocalOrigin(item.args.origin)
				}
			case ClassField | EnumAbstractField:
				final field = printer.printClassFieldDefinition(item.args, getType(), item.kind == EnumAbstractField);
				{
					definition: printCodeBlock(field, Haxe),
					origin: printer.printClassFieldOrigin(item.args.origin, item.kind)
				}
			case EnumField:
				final field = printer.printEnumFieldDefinition(item.args.field, getType());
				{
					definition: printCodeBlock(field, Haxe),
					origin: printer.printEnumFieldOrigin(item.args.origin)
				}
			case Metadata:
				{definition: printCodeBlock(item.args.name, Haxe)};
			case Define:
				final value = item.args.value;
				{definition: if (value == null) "_not defined_" else printCodeBlock('"$value"', Haxe)};
			case Literal:
				final value = item.args.name;
				final sourceText = doc.getText(hover.range);
				if (value != sourceText && getType().getDotPath() != Std_String) {
					return {definition: printCodeBlock(value, Haxe)};
				} else {
					printType();
				}
			case _:
				printType();
		}

		final expected = hover.expected;
		if (expected != null && expected.name != null && expected.name.kind == FunctionArgument) {
			var argument = expected.name.name;
			if (expected.type != null) {
				final printer = new DisplayPrinter(PathPrinting.Never);
				argument += ":" + printer.printType(expected.type);
			}
			result.additionalSections = ['*for argument `$argument`*'];
			if (expected.name.doc != null) {
				result.additionalSections.push(DocHelper.markdownFormat(expected.name.doc));
			}
		}

		return result;
	}

	function handleLegacy(params:TextDocumentPositionParams, token:CancellationToken, resolve:Null<Hover>->Void, reject:ResponseError<NoData>->Void,
			doc:HxTextDocument, offset:Int) {
		final args = ['${doc.uri.toFsPath()}@$offset@type'];
		context.callDisplay("@type", args, doc.content, token, function(result) {
			switch result {
				case DCancelled:
					resolve(null);
				case DResult(data):
					final xml = try Xml.parse(data).firstElement() catch (_:Any) null;
					if (xml == null)
						return reject.invalidXml(data);

					final s = xml.firstChild().nodeValue.trim();
					switch xml.nodeName {
						case "metadata":
							if (s.length == 0)
								return reject(new ResponseError(0, "No metadata information"));
							resolve({contents: s});
						case _:
							if (s.length == 0)
								return reject(new ResponseError(0, "No type information"));
							final type:String = switch parseDisplayType(s) {
								case DTFunction(args, ret):
									printFunctionType(args, ret);
								case DTValue(type):
									if (type == null) "unknown" else type;
							};
							final documentation = xml.get("d");
							final pos = HaxePosition.parse(xml.get("p"), doc, null, context.displayOffsetConverter);
							var range:Null<Range> = null;
							if (pos != null)
								range = pos.range;
							final definition = {definition: printCodeBlock(type, HaxeType)};
							resolve(createHover(definition, documentation, range));
					}
			}
		}, reject.handler());
	}

	function createHover(content:HoverContent, ?documentation:String, ?range:Range):Hover {
		if (documentation != null) {
			documentation = DocHelper.markdownFormat(documentation).trim();
			if (documentation != "") {
				documentation = "\n" + documentation;
			}
		}
		if (content.origin != null) {
			if (documentation == null) {
				documentation = "";
			}
			documentation = '*${content.origin}*\n' + documentation;
		}

		var sections = [content.definition];
		if (documentation != null && documentation != "") {
			sections.push(documentation);
		}
		if (content.additionalSections != null) {
			sections = sections.concat(content.additionalSections);
		}
		final hover:Hover = {
			contents: {
				kind: MarkDown,
				value: sections.join("\n\n---\n")
			}
		};
		if (range != null) {
			hover.range = range;
		}
		return hover;
	}
}

private typedef HoverContent = {
	definition:String,
	?origin:String,
	?additionalSections:Array<String>
}

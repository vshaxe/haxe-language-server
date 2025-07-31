package haxeLanguageServer.features.haxe.completion;

import haxe.display.Display.CompletionParams as HaxeCompletionParams;
import haxe.display.Display;
import haxe.display.JsonModuleTypes;
import haxe.extern.EitherType;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.helper.ImportHelper;
import haxeLanguageServer.helper.SemVer;
import haxeLanguageServer.helper.Set;
import haxeLanguageServer.helper.VscodeCommands;
import haxeLanguageServer.protocol.CompilerMetadata;
import haxeLanguageServer.protocol.DisplayPrinter;
import haxeLanguageServer.tokentree.PositionAnalyzer;
import haxeLanguageServer.tokentree.TokenContext;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.CompletionItem;
import languageServerProtocol.Types.CompletionItemKind;
import languageServerProtocol.Types.CompletionList;
import languageServerProtocol.Types.MarkupContent;
import languageServerProtocol.Types.MarkupKind;
import languageServerProtocol.protocol.Protocol.CompletionParams;
import tokentree.TokenTree;

using tokentree.TokenTreeAccessHelper;

enum abstract CompletionItemOrigin(Int) {
	final Haxe;
	final Custom;
}

typedef CompletionItemData = {
	final origin:CompletionItemOrigin;
	final ?index:Int;
}

class CompletionFeature {
	final context:Context;
	final legacy:CompletionFeatureLegacy;
	final expectedTypeCompletion:ExpectedTypeCompletion;
	final postfixCompletion:PostfixCompletion;
	final snippetCompletion:SnippetCompletion;
	final printer:DisplayPrinter;
	var previousCompletionData:Null<CompletionContextData>;

	var contextSupport:Bool;
	var markdownSupport:Bool;
	var snippetSupport:Bool;
	var commitCharactersSupport:Bool;
	var deprecatedSupport:Bool;

	public function new(context) {
		this.context = context;
		inline checkCapabilities();
		expectedTypeCompletion = new ExpectedTypeCompletion(context);
		postfixCompletion = new PostfixCompletion(context);
		snippetCompletion = new SnippetCompletion(context);
		printer = new DisplayPrinter(false, Qualified, {
			argumentTypeHints: true,
			returnTypeHint: NonVoid,
			useArrowSyntax: false,
			placeOpenBraceOnNewLine: false,
			explicitPublic: true,
			explicitPrivate: true,
			explicitNull: true
		});

		legacy = new CompletionFeatureLegacy(context, contextSupport, formatDocumentation);
	}

	function checkCapabilities() {
		final completion = context.capabilities.textDocument?.completion;
		contextSupport = completion?.contextSupport == true;
		markdownSupport = completion?.completionItem?.documentationFormat.let(kinds -> kinds.contains(MarkDown)) == true;
		snippetSupport = completion?.completionItem?.snippetSupport == true;
		commitCharactersSupport = completion?.completionItem?.commitCharactersSupport == true;
		deprecatedSupport = completion?.completionItem?.tagSupport?.valueSet.let(tags -> tags.contains(Deprecated)) == true;
	}

	public function onCompletion(params:CompletionParams, token:CancellationToken, resolve:Null<EitherType<Array<CompletionItem>, CompletionList>>->Void,
			reject:ResponseError<NoData>->Void) {
		final uri = params.textDocument.uri;
		final doc:Null<HaxeDocument> = context.documents.getHaxe(uri);
		if (doc == null || !uri.isFile()) {
			return reject.noFittingDocument(uri);
		}
		final offset = doc.offsetAt(params.position);
		final textBefore = doc.content.substring(0, offset);
		final whitespace = textBefore.length - textBefore.rtrim().length;
		final currentToken = new PositionAnalyzer(doc).resolve(params.position.translate(0, -whitespace));
		if (contextSupport && !isValidCompletionPosition(currentToken, doc, params, textBefore)) {
			return resolve({items: [], isIncomplete: false});
		}
		final handle = if (context.haxeServer.supports(DisplayMethods.Completion)) handleJsonRpc else legacy.handle;
		handle(params, token, resolve, reject, doc, offset, textBefore, currentToken);
	}

	static final autoTriggerOnSpacePattern = ~/(\b(import|using|extends|implements|from|to|case|new|cast|override)|(->)) $/;

	function isValidCompletionPosition(token:Null<TokenTree>, doc:HaxeDocument, params:CompletionParams, text:String):Bool {
		if (token == null) {
			return true;
		}
		final inComment = switch token.tok {
			case Comment(_), CommentLine(_): true;
			case _: false;
		};
		if (inComment) {
			return false;
		}
		// disable completion after `#if` and `#end`
		if (token.tok.match(Sharp("if")) || token.tok.match(Sharp("end"))) {
			return false;
		}
		// disable completion after `#if foo`
		if (token.parent?.tok.match(Sharp("if")) && token.previousSibling == null) {
			return false;
		}
		if (params.context == null) {
			return true;
		}
		return switch params.context.triggerCharacter {
			case null: true;
			case ">" if (!isAfterArrow(text)): false;
			case " " if (!autoTriggerOnSpacePattern.match(text)): false;
			case "$" if (!isInterpolationPosition(token, doc, params.position, text)): false;
			case _: true;
		}
	}

	inline function isAfterArrow(text:String):Bool {
		return text.trim().endsWith("->");
	}

	static final dollarPattern = ~/(\$+)$/;

	function isInterpolationPosition(token:Null<TokenTree>, doc, pos, text):Bool {
		final inMacroReification = token.access().findParent(t -> t.matches(Kwd(KwdMacro)).exists()).exists();
		final stringKind = PositionAnalyzer.getStringKind(token, doc, pos);

		if (stringKind != SingleQuote) {
			return inMacroReification;
		}
		if (!dollarPattern.match(text)) {
			return false;
		}
		final escaped = dollarPattern.matched(1).length % 2 == 0;
		return !escaped;
	}

	public function onCompletionResolve(item:CompletionItem, token:CancellationToken, resolve:CompletionItem->Void, reject:ResponseError<NoData>->Void) {
		final data:Null<CompletionItemData> = item.data;
		if (!context.haxeServer.supports(DisplayMethods.CompletionItemResolve)
			|| previousCompletionData == null
			|| data?.origin == Custom) {
			return resolve(item);
		}
		final index = (data?.index).sure();
		previousCompletionData.isResolve = true;
		context.callHaxeMethod(DisplayMethods.CompletionItemResolve, {index: index}, token, function(result) {
			final resolvedItem = createCompletionItem(index, result.item, previousCompletionData.sure());
			if (resolvedItem != null) {
				resolve(resolvedItem);
			} else {
				reject(ResponseError.internalError("Unable to resolve completion item."));
			}
			return null;
		}, reject.handler());
	}

	function handleJsonRpc(params:CompletionParams, token:CancellationToken, resolve:CompletionList->Void, reject:ResponseError<NoData>->Void,
			doc:HaxeDocument, offset:Int, textBefore:String, currentToken:Null<TokenTree>) {
		var wasAutoTriggered = true;
		if (params.context != null) {
			wasAutoTriggered = params.context.triggerKind == TriggerCharacter;
			if (params.context.triggerCharacter == "$") {
				wasAutoTriggered = false;
			}
		}
		final haxeParams:HaxeCompletionParams = {
			file: doc.uri.toFsPath(),
			contents: doc.content,
			offset: context.displayOffsetConverter.characterOffsetToByteOffset(doc.content, offset),
			wasAutoTriggered: wasAutoTriggered,
			meta: [CompilerMetadata.Deprecated]
		};
		final tokenContext = PositionAnalyzer.getContext(currentToken, doc, params.position);
		final position = params.position;
		final lineAfter = doc.getText({
			start: position,
			end: position.translate(1, 0)
		});
		final wordPattern = ~/\w*$/;
		wordPattern.match(textBefore);
		var replaceRange = {
			start: params.position.translate(0, -wordPattern.matched(0).length),
			end: params.position
		};

		function createCompletionWithoutHaxeResponse() {
			final token:Null<TokenTree> = doc.tokens?.getTokenAtOffset(doc.offsetAt(replaceRange.start));
			// disable snippets/keywords completion in unwanted places
			if (token != null && token.parent != null) {
				switch token.parent.tok {
					case Kwd(KwdCase):
						if (token.tok == DblDot) {
							resolve({
								items: [],
								isIncomplete: false
							});
							return;
						}
					case _:
				}
			}
			final keywords = createFieldKeywordItems(tokenContext, replaceRange, lineAfter);
			if (snippetSupport) {
				snippetCompletion.createItems({
					doc: doc,
					params: params,
					replaceRange: replaceRange,
					tokenContext: tokenContext
				}, []).then(result -> {
					resolve({
						items: keywords.concat(result.items),
						isIncomplete: false
					});
				});
			} else {
				resolve({
					items: keywords,
					isIncomplete: false
				});
			}
		}

		context.callHaxeMethod(DisplayMethods.Completion, haxeParams, token, function(result) {
			if (result == null) {
				createCompletionWithoutHaxeResponse();
				return null;
			}
			final mode = result.mode.kind;
			if (mode != TypeHint && wasAutoTriggered && isAfterArrow(textBefore)) {
				resolve({items: [], isIncomplete: false}); // avoid auto-popup after -> in arrow functions
				return null;
			}
			final importPosition = determineImportPosition(doc);
			final indent = doc.indentAt(params.position.line);

			switch (mode) {
				// the replaceRanges sent by Haxe are only trustworthy in some cases (https://github.com/HaxeFoundation/haxe/issues/8669)
				case Metadata | Toplevel if (result.replaceRange != null):
					replaceRange = result.replaceRange;

				case New | Toplevel | Implements | Extends | TypeHint | TypeRelation:
					final pathPattern = ~/\w+(\.\w+)*$/;
					if (pathPattern.match(textBefore)) {
						replaceRange.start = params.position.translate(0, -pathPattern.matched(0).length);
					}

				case _:
			}

			final displayItems = result.items;
			final data:CompletionContextData = {
				replaceRange: replaceRange,
				mode: result.mode,
				doc: doc,
				indent: indent,
				lineAfter: lineAfter,
				params: params,
				importPosition: importPosition,
				tokenContext: tokenContext,
				isResolve: false
			};

			var items = [];
			items = items.concat(postfixCompletion.createItems(data, displayItems));
			items = items.concat(expectedTypeCompletion.createItems(data));
			items = items.concat(createFieldKeywordItems(tokenContext, replaceRange, lineAfter));

			function resolveItems(itemsToIgnore:Set<DisplayItem<Dynamic>>) {
				for (i in 0...displayItems.length) {
					final displayItem = displayItems[i];
					if (itemsToIgnore.has(displayItem)) {
						continue;
					}
					final index = if (displayItem.index == null) i else displayItem.index;
					final completionItem = createCompletionItem(index, displayItem, data);
					if (completionItem != null) {
						items.push(completionItem);
					}
				}
				items = items.filter(i -> i != null);
				resolve({
					items: items,
					isIncomplete: result.isIncomplete == true
				});
			}
			if (snippetSupport && mode != Import && mode != Field) {
				snippetCompletion.createItems(data, displayItems).then(function(result) {
					items = items.concat(result.items);
					resolveItems(result.itemsToIgnore);
				});
			} else {
				resolveItems(new Set());
			}
			previousCompletionData = data;
			return displayItems.length + " items";
		}, function(error) {
			createCompletionWithoutHaxeResponse();
		});
	}

	function createFieldKeywordItems(tokenContext:TokenContext, replaceRange:Range, lineAfter:String):Array<CompletionItem> {
		final isFieldLevel = switch tokenContext {
			case Type(type) if (type.field == null): true;
			case _: false;
		}
		if (!isFieldLevel) {
			return [];
		}
		final results:Array<CompletionItem> = [];
		function create(keyword:KeywordKind):CompletionItem {
			return {
				label: keyword,
				kind: Keyword,
				textEdit: {
					newText: maybeInsert(keyword, " ", lineAfter),
					range: replaceRange
				},
				command: TriggerSuggest,
				sortText: "~~~",
				data: {
					origin: Custom
				}
			}
		}
		final keywords:Array<KeywordKind> = [Public, Private, Extern, Final, Static, Dynamic, Override, Inline, Macro];
		if (context.haxeServer.haxeVersion >= new SemVer(4, 2, 0)) {
			keywords.push(Abstract);
			keywords.push(Overload);
		}
		for (keyword in keywords) {
			results.push(create(keyword));
		}
		return results;
	}

	function createCompletionItem<T>(index:Int, item:DisplayItem<T>, data:CompletionContextData):Null<CompletionItem> {
		final completionItem:CompletionItem = switch item.kind {
			case ClassField | EnumAbstractField: createClassFieldCompletionItem(item, data);
			case EnumField: createEnumFieldCompletionItem(item, data);
			case Type: createTypeCompletionItem(item.args, data);
			case Package: createPackageCompletionItem(item.args, data);
			case Keyword: createKeywordCompletionItem(item.args, data);
			case Local: createLocalCompletionItem(item, data);
			case Module: createModuleCompletionItem(item.args, data);
			case Literal: createLiteralCompletionItem(item, data);
			case Metadata:
				if (item.args.internal) {
					null;
				} else {
					label: item.args.name,
					kind: Function
				}
			case TypeParameter: {
					label: item.args.name,
					kind: TypeParameter
				}
			// these never appear during `display/completion` right now
			case Expression: null;
			case Define: null;
			case AnonymousStructure: null;
		}

		if (completionItem == null) {
			return null;
		}

		if (completionItem.textEdit == null && data.replaceRange != null) {
			completionItem.textEdit = {range: data.replaceRange, newText: completionItem.label};
		}

		if (completionItem.documentation == null) {
			completionItem.documentation = formatDocumentation(item.getDocumentation());
		}

		if (completionItem.detail != null) {
			completionItem.detail = completionItem.detail.rtrim();
		}

		if (commitCharactersSupport) {
			final mode = data.mode.kind;
			if ((item.type != null && item.type.kind == TFun && mode != Pattern) || mode == New) {
				completionItem.commitCharacters = ["("];
			}
		}

		if (completionItem.sortText == null) {
			completionItem.sortText = "";
		}
		completionItem.sortText += Std.string(index + 1).lpad("0", 10);

		completionItem.data = {origin: Haxe, index: index};
		return completionItem;
	}

	function createClassFieldCompletionItem<T>(item:DisplayItem<Dynamic>, data:CompletionContextData):Null<CompletionItem> {
		final occurrence:ClassFieldOccurrence<T> = item.args;
		final concreteType = item.type;
		final field = occurrence.field;
		final resolution = occurrence.resolution;
		final printedOrigin = printer.printClassFieldOrigin(occurrence.origin, item.kind, "'");

		if (concreteType == null || field.meta.hasMeta(NoCompletion)) {
			return null;
		}
		if (data.mode.kind == Override) {
			return createOverrideCompletionItem(item, data, printedOrigin);
		}

		final item:CompletionItem = {
			label: field.name,
			kind: getKindForField(field, item.kind),
			detail: {
				final overloads = if (occurrence.field.overloads == null) 0 else occurrence.field.overloads.length;
				var detail = printer.printClassFieldDefinition(occurrence, concreteType, item.kind == EnumAbstractField);
				if (overloads > 0) {
					detail += ' (+$overloads overloads)';
				}
				final shadowed = if (!resolution.isQualified) " (shadowed)" else "";
				if (printedOrigin != null) {
					detail + "\n " + printedOrigin + shadowed;
				} else {
					detail + "\n " + shadowed;
				}
			},
			textEdit: {
				newText: {
					final qualifier = if (resolution.isQualified) "" else resolution.qualifier + ".";
					qualifier + switch data.mode.kind {
						case StructureField: maybeInsert(field.name, ": ", data.lineAfter);
						case Pattern: maybeInsert(field.name, ":", data.lineAfter);
						case _: field.name;
					}
				},
				range: data.replaceRange
			}
		}

		switch data.mode.kind {
			case StructureField:
				if (field.meta.hasMeta(Optional)) {
					item.label = "?" + field.name;
					item.filterText = field.name;
				}
			case _:
		}

		handleDeprecated(item, field.meta);
		return item;
	}

	function createOverrideCompletionItem<T>(item:DisplayItem<Dynamic>, data:CompletionContextData, printedOrigin:Null<String>):Null<CompletionItem> {
		final occurrence:ClassFieldOccurrence<T> = item.args;
		final concreteType = item.type;
		final field = occurrence.field;
		final importConfig = context.config.user.codeGeneration.imports;

		if (concreteType == null || concreteType.kind != TFun || field.isFinalField()) {
			return null;
		}
		final kind = field.kind.args;
		switch field.kind.kind {
			case FMethod if (kind == MethInline || kind == MethMacro):
				return null;
			case _:
		}

		final fieldFormatting = context.config.user.codeGeneration.functions.field;
		final printer = new DisplayPrinter(false, if (importConfig.enableAutoImports) Shadowed else Qualified, fieldFormatting);

		final item:CompletionItem = {
			label: field.name,
			kind: getKindForField(field, item.kind),
			textEdit: {
				newText: printer.printOverrideDefinition(field, concreteType, data.indent, true),
				range: data.replaceRange
			},
			insertTextFormat: Snippet,
			detail: "Auto-generate override" + (if (printedOrigin == null) "" else "\n" + printedOrigin),
			documentation: {
				kind: MarkDown,
				value: DocHelper.printCodeBlock("override " + printer.printOverrideDefinition(field, concreteType, data.indent, false), Haxe)
			},
			additionalTextEdits: createFunctionImportsEdit(data.doc, data.importPosition, context, concreteType, fieldFormatting)
		}
		handleDeprecated(item, field.meta);
		return item;
	}

	function getKindForField<T>(field:JsonClassField, kind:DisplayItemKind<Dynamic>):CompletionItemKind {
		if (kind == EnumAbstractField) {
			return EnumMember;
		}
		final fieldKind:JsonFieldKind<T> = field.kind;
		return switch fieldKind.kind {
			case FVar:
				if (field.isFinalField()) {
					return Field;
				}
				final read = fieldKind.args.read.kind;
				final write = fieldKind.args.write.kind;
				switch [read, write] {
					case [AccNormal, AccNormal]: Field;
					case [AccInline, _]: Constant;
					case _: Property;
				}
			case FMethod if (field.isOperator()): Operator;
			case FMethod if (field.scope == Static): Function;
			case FMethod if (field.scope == Constructor): Constructor;
			case FMethod: Method;
		}
	}

	function getKindForType<T>(type:JsonType<T>):CompletionItemKind {
		return switch type.kind {
			case TFun: Function;
			case _: Field;
		}
	}

	function createEnumFieldCompletionItem<T>(item:DisplayItem<Dynamic>, data:CompletionContextData):Null<CompletionItem> {
		if (item.type == null) {
			return null;
		}
		final occurrence:EnumFieldOccurrence<T> = item.args;
		final field:JsonEnumField = occurrence.field;
		final name = field.name;
		final textEdit:TextEdit = {
			newText: name,
			range: data.replaceRange
		};
		final result:CompletionItem = {
			label: name,
			kind: EnumMember,
			detail: {
				final definition = printer.printEnumFieldDefinition(field, item.type);
				final origin = printer.printEnumFieldOrigin(occurrence.origin, "'");
				if (origin != null) {
					definition + "\n" + origin;
				} else {
					definition;
				}
			},
			textEdit: textEdit
		};

		if (data.mode.kind == Pattern) {
			var field = printer.printEnumField(field, item.type, true, false);
			field = maybeInsertPatternColon(field, data);
			textEdit.newText = field;
			result.insertTextFormat = Snippet;
			result.command = TriggerParameterHints;
		}

		return result;
	}

	function createTypeCompletionItem(type:DisplayModuleType, data:CompletionContextData):Null<CompletionItem> {
		final mode = data.mode;
		final isImportCompletion = mode.kind == Import || mode.kind == Using;
		final importConfig = context.config.user.codeGeneration.imports;
		var autoImport = importConfig.enableAutoImports;
		if (isImportCompletion || type.path.importStatus == Shadowed) {
			autoImport = false; // need to insert the qualified name
		}

		final dotPath = new DisplayPrinter(PathPrinting.Always).printPath(type.path); // pack.Foo | pack.Foo.SubType
		if (isExcluded(dotPath)) {
			return null;
		}
		final unqualifiedName = type.path.typeName; // Foo | SubType
		final containerName = if (dotPath.contains(".")) dotPath.untilLastDot() else ""; // pack | pack.Foo

		final pathPrinting = if (isImportCompletion) Always else Qualified;
		final qualifiedName = new DisplayPrinter(pathPrinting).printPath(type.path); // unqualifiedName or dotPath depending on importStatus

		final activePackage = context.latestActiveFilePackage;
		var sortText = if (containerName == activePackage) {
			// same package
			"00";
		} else if (containerName.length == 0) {
			// non-shadowed std classes
			"01";
		} else if (type.meta.hasMeta(Deprecated)) {
			"09";
		} else {
			// everything else based on package deepness
			final diff = if (activePackage.startsWith(containerName)) {
				containerName.replace(activePackage, "");
			} else {
				containerName;
			}
			final length = diff.split(".").length;
			'${length + 2}'.lpad("0", 2);
		}
		final textEdit:TextEdit = {
			range: data.replaceRange,
			newText: if (autoImport) unqualifiedName else qualifiedName
		};
		final item:CompletionItem = {
			label: unqualifiedName + if (containerName == "") "" else " - " + dotPath,
			kind: getKindForModuleType(type),
			textEdit: textEdit,
			sortText: unqualifiedName + sortText
		};

		if (isImportCompletion) {
			textEdit.newText = maybeInsert(textEdit.newText, ";", data.lineAfter);
		} else if (importConfig.enableAutoImports && type.path.importStatus == Unimported) {
			final edit = createImportsEdit(data.doc, data.importPosition, [dotPath], importConfig.style);
			item.additionalTextEdits = [edit];
		}

		if (snippetSupport) {
			switch data.mode.kind {
				case TypeHint | Extends | Implements | StructExtension if (data.lineAfter.charCodeAt(0) != '<'.code
					&& type.hasMandatoryTypeParameters()):
					textEdit.newText += "<$1>";
					item.insertTextFormat = Snippet;
					item.command = TriggerSuggest;
				case _:
			}
		}

		if (data.mode.kind == StructExtension && data.mode.args != null) {
			final completionData:StructExtensionCompletion = data.mode.args;
			if (!completionData.isIntersectionType) {
				textEdit.newText = maybeInsert(textEdit.newText, ",", data.lineAfter);
			}
		}

		if (type.params != null) {
			item.detail = printTypeDetail(type, containerName);
		}

		handleDeprecated(item, type.meta);
		return item;
	}

	function getKindForModuleType(type:DisplayModuleType):CompletionItemKind {
		return switch type.kind {
			case Class: Class;
			case Interface: Interface;
			case Enum: Enum;
			case Abstract: Class;
			case EnumAbstract: Enum;
			case TypeAlias: Interface;
			case Struct: Struct;
		}
	}

	function formatDocumentation(doc:Null<String>):Null<EitherType<String, MarkupContent>> {
		if (doc == null) {
			return null;
		}
		if (markdownSupport) {
			return {
				kind: MarkupKind.MarkDown,
				value: DocHelper.markdownFormat(doc)
			};
		}
		return DocHelper.extractText(doc);
	}

	function printTypeDetail(type:DisplayModuleType, containerName:String):String {
		return printer.printEmptyTypeDefinition(type) + "\n" + switch type.path.importStatus {
			case null: "";
			case Imported: "(imported)";
			case Unimported: "Auto-import from '" + containerName + "'";
			case Shadowed: "(shadowed)";
		}
	}

	function createPackageCompletionItem(pack:Package, data:CompletionContextData):Null<CompletionItem> {
		final path = pack.path;
		final dotPath = path.pack.join(".");
		if (isExcluded(dotPath)) {
			return null;
		}
		final text = if (data.mode.kind == Field) path.pack[path.pack.length - 1] else dotPath;
		return {
			label: text,
			kind: Module,
			detail: 'package $dotPath',
			textEdit: {
				newText: maybeInsert(text, ".", data.lineAfter),
				range: data.replaceRange
			},
			command: TriggerSuggest
		};
	}

	function createKeywordCompletionItem(keyword:Keyword, data:CompletionContextData):CompletionItem {
		final textEdit:TextEdit = {
			newText: keyword.name,
			range: data.replaceRange
		};
		final item:CompletionItem = {
			label: keyword.name,
			kind: Keyword,
			textEdit: textEdit
		}

		if (data.mode.kind == TypeRelation || keyword.name == New || keyword.name == Inline) {
			item.command = TriggerSuggest;
		}
		if (data.mode.kind == TypeDeclaration) {
			switch keyword.name {
				case Import | Using | Final | Extern | Private:
					item.command = TriggerSuggest;
				case _:
			}
		}

		inline function maybeAddSpace() {
			textEdit.newText = maybeInsert(textEdit.newText, " ", data.lineAfter);
		}

		switch keyword.name {
			case Extends | Implements:
				textEdit.newText += " ";
			// TODO: make it configurable for these, since not all code styles want spaces there
			case Else | Do | Switch:
				maybeAddSpace();
			case If | For | While | Catch:
				if (snippetSupport) {
					item.insertTextFormat = Snippet;
					textEdit.newText = '${keyword.name} ($1)';
				} else {
					maybeAddSpace();
				}
			// do nothing for these, you might not want a space after
			case Break | Cast | Continue | Default | Return | Package:
				// assume a space is needed for all the rest
			case _:
				maybeAddSpace();
		}

		return item;
	}

	function createLocalCompletionItem<T>(item:DisplayItem<Dynamic>, data:CompletionContextData):Null<CompletionItem> {
		final local:DisplayLocal<T> = item.args;
		if (item.type == null || local.name == "_") {
			return null; // naming vars "_" is a common convention for ignoring them
		}
		return {
			label: local.name,
			kind: if (local.origin == LocalFunction) Method else Variable,
			detail: {
				final type = printer.printLocalDefinition(local, item.type);
				final origin = local.origin != null ? printer.printLocalOrigin(local.origin) : "";
				if (origin.length == 0)
					type;
				else
					'$type \n($origin)';
			}
		};
	}

	function createModuleCompletionItem(module:Module, data:CompletionContextData):Null<CompletionItem> {
		final path = module.path;
		final dotPath = path.pack.concat([path.moduleName]).join(".");
		return if (isExcluded(dotPath)) {
			null;
		} else {
			{
				label: path.moduleName,
				kind: Folder,
				detail: 'module $dotPath'
			}
		}
	}

	function createLiteralCompletionItem<T>(item:DisplayItem<Dynamic>, data:CompletionContextData):Null<CompletionItem> {
		if (item.type == null) {
			return null;
		}
		final literal:DisplayLiteral<T> = item.args;
		final result:CompletionItem = {
			label: literal.name,
			kind: Keyword,
			detail: printer.printType(item.type)
		};
		switch literal.name {
			case "null" | "true" | "false":
				result.textEdit = {
					range: data.replaceRange,
					newText: maybeInsertPatternColon(literal.name, data)
				};
			case _:
		}
		return result;
	}

	function maybeInsert(text:String, token:String, lineAfter:String):String {
		return if (lineAfter.charAt(0) == token.charAt(0)) text else text + token;
	}

	function maybeInsertPatternColon(text:String, data:CompletionContextData):String {
		final info:Null<PatternCompletion<Dynamic>> = data.mode.args;
		if (info == null || info.isOutermostPattern) {
			return maybeInsert(text, ":", data.lineAfter);
		}
		return text;
	}

	function handleDeprecated(item:CompletionItem, meta:JsonMetadata) {
		if (deprecatedSupport && meta.hasMeta(Deprecated)) {
			if (item.tags == null) {
				item.tags = [];
			}
			item.tags.push(Deprecated);
		}
	}

	function isExcluded(dotPath:String):Bool {
		final excludes = context.config.user.exclude;
		if (excludes == null) {
			return false;
		}
		for (exclude in excludes) {
			if (dotPath.startsWith(exclude)) {
				return true;
			}
		}
		return false;
	}
}

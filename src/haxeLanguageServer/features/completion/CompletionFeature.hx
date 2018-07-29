package haxeLanguageServer.features.completion;

import haxe.ds.Option;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import haxeLanguageServer.protocol.Display;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.helper.ImportHelper;
import haxeLanguageServer.protocol.helper.DisplayPrinter;
import languageServerProtocol.protocol.Protocol.CompletionParams;
import languageServerProtocol.Types.CompletionItem;
import languageServerProtocol.Types.CompletionItemKind;
import haxe.display.JsonModuleTypes;
import haxe.extern.EitherType;

enum abstract CompletionItemOrigin(Int) {
    var Haxe;
    var Custom;
}

typedef CompletionItemData = {
    var origin:CompletionItemOrigin;
    var ?index:Int;
}

class CompletionFeature {
    final context:Context;
    final legacy:CompletionFeatureLegacy;
    final expectedTypeCompletion:ExpectedTypeCompletion;
    final postfixCompletion:PostfixCompletion;
    final printer:DisplayPrinter;
    final triggerSuggest:Command;
    final triggerParameterHints:Command;

    var previousCompletionData:CompletionContextData;
    var contextSupport:Bool;
    var markdownSupport:Bool;
    var snippetSupport:Bool;
    var commitCharactersSupport:Bool;
    var deprecatedSupport:Bool;

    public function new(context) {
        this.context = context;
        checkCapabilities();
        legacy = new CompletionFeatureLegacy(context, contextSupport, formatDocumentation);
        expectedTypeCompletion = new ExpectedTypeCompletion(context);
        postfixCompletion = new PostfixCompletion();
        printer = new DisplayPrinter(false, null, {
            argumentTypeHints: true,
            returnTypeHint: NonVoid,
            explicitPublic: true,
            explicitPrivate: true,
            explicitNull: true
        });
        context.protocol.onRequest(Methods.Completion, onCompletion);
        context.protocol.onRequest(Methods.CompletionItemResolve, onCompletionItemResolve);

        triggerSuggest = {
            title: "Trigger Suggest",
            command: "editor.action.triggerSuggest",
            arguments: []
        };
        triggerParameterHints = {
            title: "Trigger Parameter Hints",
            command: "editor.action.triggerParameterHints",
            arguments: []
        };
    }

    function checkCapabilities() {
        contextSupport = false;
        markdownSupport = false;

        var textDocument = context.capabilities.textDocument;
        if (textDocument == null) return;
        var completion = textDocument.completion;
        if (completion == null) return;

        contextSupport = completion.contextSupport == true;

        var completionItem = completion.completionItem;
        if (completionItem == null) return;

        var documentationFormat = completionItem.documentationFormat;
        if (documentationFormat != null) {
            markdownSupport = documentationFormat.indexOf(MarkDown) != -1;
        }

        if (completionItem.snippetSupport) {
            snippetSupport = true;
        }

        if (completionItem.commitCharactersSupport) {
            commitCharactersSupport = true;
        }

        if (completionItem.deprecatedSupport) {
            deprecatedSupport = true;
        }
    }

    function onCompletion(params:CompletionParams, token:CancellationToken, resolve:Array<CompletionItem>->Void, reject:ResponseError<NoData>->Void) {
        var doc = context.documents.get(params.textDocument.uri);
        var offset = doc.offsetAt(params.position);
        var textBefore = doc.content.substring(0, offset);
        if (contextSupport && isInvalidCompletionPosition(params, textBefore)) {
            return resolve([]);
        }
        var handle = if (context.haxeServer.supports(DisplayMethods.Completion)) handleJsonRpc else legacy.handle;
        handle(params, token, resolve, reject, doc, offset, textBefore);
    }

    static final autoTriggerOnSpacePattern = ~/(\b(import|using|extends|implements|case|new|cast|override)|(->)) $/;
    function isInvalidCompletionPosition(params:CompletionParams, text:String):Bool {
        return switch (params.context.triggerCharacter) {
            case ">" if (!isAfterArrow(text)): true;
            case " " if (!autoTriggerOnSpacePattern.match(text)): true;
            case _: false;
        }
    }

    inline function isAfterArrow(text:String):Bool {
        return text.trim().endsWith("->");
    }

    function onCompletionItemResolve(item:CompletionItem, token:CancellationToken, resolve:CompletionItem->Void, reject:ResponseError<NoData>->Void) {
        var data:CompletionItemData = item.data;
        if (!context.haxeServer.supports(DisplayMethods.CompletionItemResolve) || previousCompletionData == null || data.origin == Custom) {
            return resolve(item);
        }
        context.callHaxeMethod(DisplayMethods.CompletionItemResolve, {index: item.data.index}, token, result -> {
            resolve(createCompletionItem(data.index, result.item, previousCompletionData));
            return null;
        }, error -> {
            reject(ResponseError.internalError(error));
        });
    }

    function handleJsonRpc(params:CompletionParams, token:CancellationToken, resolve:Array<CompletionItem>->Void, reject:ResponseError<NoData>->Void, doc:TextDocument, offset:Int, textBefore:String) {
        var wasAutoTriggered = params.context == null ? true : params.context.triggerKind == TriggerCharacter;
        var haxeParams = {
            file: doc.fsPath,
            contents: doc.content,
            offset: offset,
            wasAutoTriggered: wasAutoTriggered,
        };
        context.callHaxeMethod(DisplayMethods.Completion, haxeParams, token, result -> {
            if (result.mode.kind != TypeHint && wasAutoTriggered && isAfterArrow(textBefore)) {
                resolve([]); // avoid auto-popup after -> in arrow functions
                return null;
            }
            var importPosition = ImportHelper.getImportPosition(doc);
            var indent = doc.indentAt(params.position.line);
            var position = params.position;
            var lineAfter = doc.getText({
                start: position,
                end: position.translate(1, 0)
            });
            var data:CompletionContextData = {
                replaceRange: result.replaceRange,
                mode: result.mode,
                doc: doc,
                indent: indent,
                lineAfter: lineAfter,
                completionPosition: params.position,
                importPosition: importPosition,
            };
            var items = [];
            for (i in 0...result.items.length) {
                var completionItem = createCompletionItem(i, result.items[i], data);
                if (completionItem != null) {
                    items.push(completionItem);
                }
            };
            items = items.concat(postfixCompletion.createItems(data));
            items = items.concat(expectedTypeCompletion.createItems(data));
            resolve(items);
            previousCompletionData = data;
            return items.length + " items";
        }, error -> reject(ResponseError.internalError(error)));
    }

    function createCompletionItem<T>(index:Int, item:DisplayItem<T>, data:CompletionContextData):CompletionItem {
        var completionItem:CompletionItem = switch (item.kind) {
            case ClassField | EnumAbstractField: createClassFieldCompletionItem(item, data);
            case EnumField: createEnumFieldCompletionItem(item, data);
            case Type: createTypeCompletionItem(item.args, data);
            case Package: createPackageCompletionItem(item.args, data);
            case Keyword: createKeywordCompletionItem(item.args, data);
            case Local: createLocalCompletionItem(item, data);
            case Module: createModuleCompletionItem(item.args, data);
            case Literal: {
                    label: item.args.name,
                    kind: Keyword,
                    detail: printer.printType(item.type)
                }
            case Metadata: {
                    label: item.args.name,
                    kind: Function
                }
            case TypeParameter: {
                    label: item.args.name,
                    kind: TypeParameter
                }
            // these never appear during `display/completion` right now
            case Expression: null;
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
            if ((item.type != null && item.type.kind == TFun) || data.mode.kind == New || data.mode.kind == Metadata) {
                completionItem.commitCharacters = ["("];
            }
        }

        if (completionItem.sortText == null) {
            completionItem.sortText = "";
        }
        completionItem.sortText += StringTools.lpad(Std.string(index + 1), "0", 10);

        completionItem.data = {origin: Haxe, index: index};
        return completionItem;
    }

    function createClassFieldCompletionItem<T>(item:DisplayItem<Dynamic>, data:CompletionContextData):CompletionItem {
        var occurrence:ClassFieldOccurrence<T> = item.args;
        var concreteType = item.type;
        var field = occurrence.field;
        var resolution = occurrence.resolution;
        var printedOrigin = printer.printClassFieldOrigin(occurrence.origin, item.kind, "'");

        if (data.mode.kind == Override) {
            return createOverrideCompletionItem(item, data, printedOrigin);
        }

        var item:CompletionItem = {
            label: field.name,
            kind: getKindForField(field, item.kind),
            detail: {
                var overloads = if (occurrence.field.overloads == null) 0 else occurrence.field.overloads.length;
                var detail = printer.printClassFieldDefinition(occurrence, concreteType, item.kind == EnumAbstractField);
                if (overloads > 0) {
                    detail += ' (+$overloads overloads)';
                }
                var shadowed = if (!resolution.isQualified) " (shadowed)" else "";
                switch (printedOrigin) {
                    case Some(v): detail + "\n" + v + shadowed;
                    case None: detail + "\n" + shadowed;
                }
            },
            textEdit: {
                newText: {
                    var qualifier = if (resolution.isQualified) "" else resolution.qualifier + ".";
                    qualifier + switch (data.mode.kind) {
                        case StructureField: maybeInsert(field.name, ": ", data.lineAfter);
                        case Pattern: maybeInsert(field.name, ":", data.lineAfter);
                        case _: field.name;
                    }
                },
                range: data.replaceRange
            }
        }

        switch (data.mode.kind) {
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

    function createOverrideCompletionItem<T>(item:DisplayItem<Dynamic>, data:CompletionContextData, printedOrigin:Option<String>):CompletionItem {
        var occurrence:ClassFieldOccurrence<T> = item.args;
        var concreteType = item.type;
        var field = occurrence.field;
        var importConfig = context.config.codeGeneration.imports;

        if (concreteType.kind != TFun || field.meta.hasMeta(Final)) {
            return null;
        }
        switch (field.kind.kind) {
            case FMethod if (field.kind.args == MethInline): return null;
            case _:
        }

        var fieldFormatting = context.config.codeGeneration.functions.field;
        var printer = new DisplayPrinter(false,
            if (importConfig.enableAutoImports) Shadowed else Qualified,
            fieldFormatting
        );

        var item:CompletionItem = {
            label: field.name,
            kind: getKindForField(field, item.kind),
            textEdit: {
                newText: printer.printOverrideDefinition(field, concreteType, data.indent, true),
                range: data.replaceRange
            },
            insertTextFormat: Snippet,
            detail: "Auto-generate override" + switch (printedOrigin) {
                case Some(v): "\n" + v;
                case None: "";
            },
            documentation: {
                kind: MarkDown,
                value: DocHelper.printCodeBlock("override " +
                    printer.printOverrideDefinition(field, concreteType, data.indent, false), Haxe)
            },
            additionalTextEdits: ImportHelper.createFunctionImportsEdit(data.doc,
                data.importPosition, context, concreteType, fieldFormatting)
        }
        handleDeprecated(item, field.meta);
        return item;
    }

    function getKindForField<T>(field:JsonClassField, kind:DisplayItemKind<Dynamic>):CompletionItemKind {
        var fieldKind:JsonFieldKind<T> = field.kind;
        return switch (fieldKind.kind) {
            case FVar:
                var read = fieldKind.args.read.kind;
                var write = fieldKind.args.write.kind;
                switch [read, write] {
                    case [AccNormal, AccNormal]: Field;
                    case [AccNormal, AccCtor]: Field; // final
                    case [AccNormal, AccNever]: Field; // static final
                    case [AccInline, _] if (kind == EnumAbstractField): EnumMember;
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
        return switch (type.kind) {
            case TFun: Function;
            case _: Field;
        }
    }

    function createEnumFieldCompletionItem<T>(item:DisplayItem<Dynamic>, data:CompletionContextData):CompletionItem {
        var occurrence:EnumFieldOccurrence<T> = item.args;
        var field:JsonEnumField = occurrence.field;
        var name = field.name;
        return {
            label: name,
            kind: EnumMember,
            detail: {
                var definition = printer.printEnumFieldDefinition(field, item.type);
                var origin = printer.printEnumFieldOrigin(occurrence.origin, "'");
                switch (origin) {
                    case Some(v): definition += "\n" + v;
                    case None:
                }
                definition;
            },
            textEdit: {
                newText: {
                    if (data.mode.kind == Pattern) {
                        var field = printer.printEnumField(field, item.type, true, false);
                        field = maybeInsert(field, ":", data.lineAfter);
                        field;
                    } else {
                        name;
                    }
                },
                range: data.replaceRange
            },
            insertTextFormat: if (data.mode.kind == Pattern) Snippet else PlainText
        };
    }

    function createTypeCompletionItem(type:DisplayModuleType, data:CompletionContextData):CompletionItem {
        var isImportCompletion = data.mode.kind == Import || data.mode.kind == Using;
        var importConfig = context.config.codeGeneration.imports;
        var autoImport = importConfig.enableAutoImports;
        if (isImportCompletion || type.path.importStatus == Shadowed) {
            autoImport = false; // need to insert the qualified name
        }

        var dotPath = new DisplayPrinter(PathPrinting.Always).printPath(type.path); // pack.Foo | pack.Foo.SubType
        if (isExcluded(dotPath)) {
            return null;
        }
        var unqualifiedName = type.path.typeName; // Foo | SubType
        var containerName = if (dotPath.indexOf(".") == -1) "" else dotPath.untilLastDot(); // pack | pack.Foo
        var qualifiedName = printer.printPath(type.path); // unqualifiedName or dotPath depending on importStatus

        var item:CompletionItem = {
            label: unqualifiedName + if (containerName == "") "" else " - " + dotPath,
            kind: getKindForModuleType(type),
            textEdit: {
                range: data.replaceRange,
                newText: if (autoImport) unqualifiedName else qualifiedName
            },
            sortText: unqualifiedName
        };

        if (isImportCompletion) {
            item.textEdit.newText = maybeInsert(item.textEdit.newText, ";", data.lineAfter);
        } else if (importConfig.enableAutoImports && type.path.importStatus == Unimported) {
            var edit = ImportHelper.createImportsEdit(data.doc, data.importPosition, [dotPath], importConfig.style);
            item.additionalTextEdits = [edit];
        }

        if (snippetSupport) {
            switch (data.mode.kind) {
                case TypeHint | Extends | Implements | StructExtension if (type.hasMandatoryTypeParameters()):
                    item.textEdit.newText += "<$1>";
                    item.insertTextFormat = Snippet;
                case _:
            }
        }

        if (data.mode.kind == StructExtension && data.mode.args != null) {
            var completionData:StructExtensionCompletion = data.mode.args;
            if (!completionData.isIntersectionType) {
                item.textEdit.newText = maybeInsert(item.textEdit.newText, ",", data.lineAfter);
            }
        }

        if (type.params != null) {
            item.detail = printTypeDetail(type, containerName);
        }

        handleDeprecated(item, type.meta);
        return item;
    }

    function getKindForModuleType(type:DisplayModuleType):CompletionItemKind {
        return switch (type.kind) {
            case Class: Class;
            case Interface: Interface;
            case Enum: Enum;
            case Abstract: Class;
            case EnumAbstract: Enum;
            case TypeAlias: Interface;
            case Struct: Struct;
        }
    }

    function formatDocumentation(doc:String):EitherType<String, MarkupContent> {
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
        var detail = printer.printEmptyTypeDefinition(type) + "\n";
        switch (type.path.importStatus) {
            case Imported:
                detail += "(imported)";
            case Unimported:
                detail += "Auto-import from '" + containerName + "'";
            case Shadowed:
                detail += "(shadowed)";
        }
        return detail;
    }

    function createPackageCompletionItem(pack:Package, data:CompletionContextData):CompletionItem {
        var path = pack.path;
        var dotPath = path.pack.join(".");
        if (isExcluded(dotPath)) {
            return null;
        }
        var text = if (data.mode.kind == Field) path.pack[path.pack.length - 1] else dotPath;
        return {
            label: text,
            kind: Module,
            detail: 'package $dotPath',
            textEdit: {
                newText: maybeInsert(text, ".", data.lineAfter),
                range: data.replaceRange
            },
            command: triggerSuggest
        };
    }

    function createKeywordCompletionItem(keyword:Keyword, data:CompletionContextData):CompletionItem {
        var item:CompletionItem = {
            label: keyword.name,
            kind: Keyword,
            textEdit: {
                newText: keyword.name,
                range: data.replaceRange
            }
        }

        if (data.mode.kind == TypeRelation || keyword.name == New) {
            item.command = triggerSuggest;
        }

        switch (keyword.name) {
            case Implements | Extends
                | Function | Var
                | Case | Try | New | Throw | Untyped | Macro:
                item.textEdit.newText += " ";
            // TODO: make it configurable for these, since not all code styles want spaces there
            case Else | Do | Switch:
                item.textEdit.newText += " ";
            case If | For | While | Catch:
                if (snippetSupport) {
                    item.insertTextFormat = Snippet;
                    item.textEdit.newText = '${keyword.name} ($1)';
                } else {
                    item.textEdit.newText += " ";
                }
            case _:
        }

        return item;
    }

    function createLocalCompletionItem<T>(item:DisplayItem<Dynamic>, data:CompletionContextData):CompletionItem {
        var local:DisplayLocal<T> = item.args;
        if (local.name == "_") {
            return null; // naming vars "_" is a common convention for ignoring them
        }
        return {
            label: local.name,
            kind: if (local.origin == LocalFunction) Method else Variable,
            detail: {
                var type = printer.printLocalDefinition(local, item.type);
                var origin = printer.printLocalOrigin(local.origin);
                '$type \n($origin)';
            }
        };
    }

    function createModuleCompletionItem(module:Module, data:CompletionContextData):CompletionItem {
        var path = module.path;
        var dotPath = path.pack.concat([path.moduleName]).join(".");
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

    static final wordRegex = ~/^\w*/;
    function maybeInsert(text:String, token:String, lineAfter:String):String {
        lineAfter = wordRegex.replace(lineAfter, "");
        return if (lineAfter.charAt(0) == token.charAt(0)) text else text + token;
    }

    function handleDeprecated(item:CompletionItem, meta:JsonMetadata) {
        if (deprecatedSupport && meta.hasMeta(Deprecated)) {
            item.deprecated = true;
        }
    }

    function isExcluded(dotPath:String):Bool {
        var excludes = context.config.exclude;
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

package haxeLanguageServer.features.completion;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import haxeLanguageServer.protocol.Display;
import haxeLanguageServer.protocol.Display.CompletionItem as HaxeCompletionItem;
import haxeLanguageServer.protocol.Display.CompletionItemKind as HaxeCompletionItemKind;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.helper.ImportHelper;
import haxeLanguageServer.protocol.helper.DisplayPrinter;
import languageServerProtocol.protocol.Protocol.CompletionParams;
import languageServerProtocol.Types.CompletionItem;
import languageServerProtocol.Types.CompletionItemKind;
import haxe.display.JsonModuleTypes;
import haxe.extern.EitherType;

private typedef PreviousCompletionResult = {
    var doc:TextDocument;
    var replaceRange:Range;
    var kind:CompletionModeKind<Dynamic>;
    var indent:String;
}

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

    var previousCompletion:PreviousCompletionResult;
    var contextSupport:Bool;
    var markdownSupport:Bool;
    var snippetSupport:Bool;
    var commitCharactersSupport:Bool;

    public function new(context) {
        this.context = context;
        checkCapabilities();
        legacy = new CompletionFeatureLegacy(context, contextSupport, formatDocumentation);
        expectedTypeCompletion = new ExpectedTypeCompletion();
        postfixCompletion = new PostfixCompletion();
        printer = new DisplayPrinter();
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
        if (!context.haxeServer.supports(DisplayMethods.CompletionItemResolve) || previousCompletion == null || data.origin == Custom) {
            return resolve(item);
        }
        var importPosition = ImportHelper.getImportPosition(previousCompletion.doc);
        context.callHaxeMethod(DisplayMethods.CompletionItemResolve, {index: item.data.index}, token, result -> {
            resolve(createCompletionItem(data.index, result.item, previousCompletion.doc, previousCompletion.replaceRange, importPosition, previousCompletion.kind, previousCompletion.indent));
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
            previousCompletion = {
                doc: doc,
                kind: result.mode.kind,
                replaceRange: result.replaceRange,
                indent: indent
            };
            var items = [];
            for (i in 0...result.items.length) {
                var completionItem = createCompletionItem(i, result.items[i], doc, result.replaceRange, importPosition, result.mode.kind, indent);
                if (completionItem != null) {
                    items.push(completionItem);
                }
            };
            items = items.concat(postfixCompletion.createItems(result.mode, params.position, doc));
            items = items.concat(expectedTypeCompletion.createItems(result.mode, params.position, doc, textBefore));
            resolve(items);
            return items.length + " items";
        }, error -> reject(ResponseError.internalError(error)));
    }

    function createCompletionItem<T>(index:Int, item:HaxeCompletionItem<T>, doc:TextDocument, replaceRange:Range, importPosition:Position, mode:CompletionModeKind<Dynamic>, indent:String):CompletionItem {
        var completionItem:CompletionItem = switch (item.kind) {
            case ClassField | EnumAbstractField: createClassFieldCompletionItem(item, doc, replaceRange, mode, indent, importPosition);
            case EnumField: createEnumFieldCompletionItem(item, replaceRange, mode);
            case Type: createTypeCompletionItem(item.args, doc, replaceRange, importPosition, mode);
            case Package: createPackageCompletionItem(item.args, replaceRange, mode);
            case Keyword: createKeywordCompletionItem(item.args, replaceRange, mode);
            case Local: {
                    label: item.args.name,
                    kind: Variable,
                    detail: {
                        var type = printer.printLocalDefinition(item.args, item.type);
                        var origin = printer.printLocalOrigin(item.args.origin);
                        '$type \n($origin)';
                    }
                }
            case Module:
                var path = item.args.path;
                {
                    label: path.name,
                    kind: Folder,
                    detail: 'module ${path.pack.concat([path.name]).join(".")}'
                }
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
            case Expression: return null;
            case AnonymousStructure: return null;
        }

        if (completionItem == null) {
            return null;
        }

        if (completionItem.textEdit == null && replaceRange != null) {
            completionItem.textEdit = {range: replaceRange, newText: completionItem.label};
        }

        if (completionItem.documentation == null) {
            completionItem.documentation = formatDocumentation(item.getDocumentation());
        }

        if (commitCharactersSupport) {
            if ((item.type != null && item.type.kind == TFun) || mode == New) {
                completionItem.commitCharacters = ["("];
            }
        }

        completionItem.sortText = StringTools.lpad(Std.string(index), "0", 10);
        completionItem.data = {origin: Haxe, index: index};
        return completionItem;
    }

    function createClassFieldCompletionItem<T>(item:HaxeCompletionItem<Dynamic>, doc:TextDocument, replaceRange:Range, mode:CompletionModeKind<Dynamic>, indent:String, importPosition:Position):CompletionItem {
        var usage:ClassFieldUsage<T> = item.args;
        var concreteType = item.type; // this has importStatus, applied type params etc, which field.type does not
        var field = usage.field;
        if (mode == Override) {
            if (concreteType.kind != TFun || field.meta.hasMeta(Final)) {
                return null;
            }
            switch (field.kind.kind) {
                case FMethod if (field.kind.args == MethInline): return null;
                case _:
            }
        }

        var importConfig = context.config.codeGeneration.imports;
        var resolution = usage.resolution;
        var item:CompletionItem = {
            label: field.name,
            kind: getKindForField(field, item.kind),
            detail: {
                var overloads = if (usage.field.overloads == null) 0 else usage.field.overloads.length;
                var detail = printer.printClassFieldDefinition(usage, concreteType, item.kind == EnumAbstractField);
                if (overloads > 0) {
                    detail += ' (+$overloads overloads)';
                }
                var origin = printer.printClassFieldOrigin(usage.origin, item.kind, "'");
                var shadowed = if (!resolution.isQualified) " (shadowed)" else "";
                switch (origin) {
                    case Some(origin): detail + "\n" + origin + shadowed;
                    case None: detail + "\n" + shadowed;
                }
            },
            textEdit: {
                newText: {
                    var qualifier = if (resolution.isQualified) "" else resolution.qualifier + ".";
                    qualifier + switch (mode) {
                        case StructureField: field.name + ": ";
                        case Pattern: field.name + ":";
                        case Override if (concreteType.kind == TFun):
                            var printer = new DisplayPrinter(false,
                                if (importConfig.enableAutoImports) Shadowed else Qualified,
                                context.config.codeGeneration.functions.field
                            );
                            printer.printOverrideDefinition(field, concreteType, indent);
                        case _: field.name;
                    }
                },
                range: replaceRange
            }
        }

        switch (mode) {
            case Override:
                item.insertTextFormat = Snippet;
                if (importConfig.enableAutoImports) {
                    var printer = new DisplayPrinter(false, Always);
                    item.additionalTextEdits = concreteType.resolveImports().map(path ->
                        ImportHelper.createImportEdit(doc, importPosition, printer.printPath(path), importConfig.style)
                    );
                }
            case StructureField:
                if (field.meta.hasMeta(Optional)) {
                    item.label = "?" + field.name;
                    item.filterText = field.name;
                }
            case _:
        }

        return item;
    }

    function getKindForField<T>(field:JsonClassField, kind:HaxeCompletionItemKind<Dynamic>):CompletionItemKind {
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

    function createEnumFieldCompletionItem<T>(item:HaxeCompletionItem<Dynamic>, replaceRange:Range, mode:CompletionModeKind<Dynamic>):CompletionItem {
        var usage:EnumValueUsage<T> = item.args;
        var field:JsonEnumField = usage.field;
        var name = field.name;
        return {
            label: name,
            kind: EnumMember,
            detail: {
                var definition = printer.printEnumFieldDefinition(field, item.type);
                var origin = printer.printEnumFieldOrigin(usage.origin, "'");
                switch (origin) {
                    case Some(v): definition += "\n" + v;
                    case None:
                }
                definition;
            },
            textEdit: {
                newText: if (mode == Pattern) printer.printEnumField(field, item.type, true, false) + ":" else name,
                range: replaceRange
            },
            insertTextFormat: if (mode == Pattern) Snippet else PlainText
        };
    }

    function createTypeCompletionItem(type:ModuleType, doc:TextDocument, replaceRange:Range, importPosition:Position, mode:CompletionModeKind<Dynamic>):CompletionItem {
        var isImportCompletion = mode == Import || mode == Using;
        var importConfig = context.config.codeGeneration.imports;
        var autoImport = importConfig.enableAutoImports;
        if (isImportCompletion || type.importStatus == Shadowed) {
            autoImport = false; // need to insert the qualified name
        }

        var qualifiedName = printer.printQualifiedTypePath(type); // pack.Foo | pack.Foo.SubType
        var unqualifiedName = type.name; // Foo | SubType
        var containerName = if (qualifiedName.indexOf(".") == -1) "" else qualifiedName.untilLastDot(); // pack | pack.Foo

        var item:CompletionItem = {
            label: unqualifiedName + if (containerName == "") "" else " - " + qualifiedName,
            kind: getKindForModuleType(type),
            textEdit: {
                range: replaceRange,
                newText: if (autoImport) unqualifiedName else qualifiedName
            }
        };

        if (isImportCompletion) {
            item.textEdit.newText += ";";
        } else {
            switch (type.importStatus) {
                case Imported:
                case Unimported:
                    var edit = ImportHelper.createImportEdit(doc, importPosition, qualifiedName, importConfig.style);
                    item.additionalTextEdits = [edit];
                case Shadowed:
            }
        }

        if (snippetSupport) {
            switch (mode) {
                case TypeHint | Extends | Implements | StructExtension if (hasMandatoryTypeParameters(type)):
                    item.textEdit.newText += "<$1>";
                    item.insertTextFormat = Snippet;
                case _:
            }
        }

        if (mode == StructExtension) {
            item.textEdit.newText += ",";
        }

        if (type.params != null) {
            item.detail = printTypeDetail(type, containerName);
        }

        return item;
    }

    function hasMandatoryTypeParameters(type:ModuleType):Bool {
        // Dynamic is a special case regarding this in the compiler
        if (type.name == "Dynamic" && type.pack.length == 0) {
            return false;
        }
        return type.params != null && type.params.length > 0;
    }

    function getKindForModuleType(type:ModuleType):CompletionItemKind {
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

    function printTypeDetail(type:ModuleType, containerName:String):String {
        var detail = printer.printEmptyTypeDefinition(type) + "\n";
        switch (type.importStatus) {
            case Imported:
                detail += "(imported)";
            case Unimported:
                detail += "Auto-import from '" + containerName + "'";
            case Shadowed:
                detail += "(shadowed)";
        }
        return detail;
    }

    function createPackageCompletionItem(pack:Package, replaceRange:Range, mode:CompletionModeKind<Dynamic>):CompletionItem {
        var path = pack.path;
        var dotPath = path.pack.concat([path.name]).join(".");
        var text = if (mode == Field) path.name else dotPath;
        return {
            label: text,
            kind: Module,
            detail: 'package $dotPath',
            textEdit: {
                newText: text + ".",
                range: replaceRange
            },
            command: triggerSuggest
        };
    }

    function createKeywordCompletionItem(keyword:Keyword, replaceRange:Range, mode:CompletionModeKind<Dynamic>):CompletionItem {
        var item:CompletionItem = {
            label: keyword.name,
            kind: Keyword,
            textEdit: {
                newText: keyword.name,
                range: replaceRange
            }
        }

        if (mode == TypeRelation || keyword.name == New) {
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
}

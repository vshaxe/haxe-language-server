package haxeLanguageServer.features.completion;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import haxeLanguageServer.protocol.Display;
import haxeLanguageServer.protocol.Display.CompletionItem as HaxeCompletionItem;
import haxeLanguageServer.protocol.Display.CompletionItemKind as HaxeCompletionItemKind;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.helper.ImportHelper;
import haxeLanguageServer.protocol.helper.TypePrinter;
import languageServerProtocol.protocol.Protocol.CompletionParams;
import languageServerProtocol.Types.CompletionItem;
import languageServerProtocol.Types.CompletionItemKind;
import haxe.display.JsonModuleTypes;
import haxe.extern.EitherType;
using Lambda;

private typedef PreviousCompletionResult = {
    var doc:TextDocument;
    var replaceRange:Range;
    var kind:CompletionModeKind<Dynamic>;
}

enum abstract CompletionItemOrigin(Int) {
    var Haxe = 0;
    var Custom = 1;
}

typedef CompletionItemData = {
    var origin:CompletionItemOrigin;
    @:optional var index:Int;
}

class CompletionFeature {
    final context:Context;
    final legacy:CompletionFeatureLegacy;
    final expectedTypeCompletion:ExpectedTypeCompletion;
    final postfixCompletion:PostfixCompletion;
    final printer:TypePrinter;
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
        printer = new TypePrinter();
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
        var handle = if (context.haxeServer.capabilities.completionProvider) handleJsonRpc else legacy.handle;
        handle(params, token, resolve, reject, doc, offset, textBefore);
    }

    static final autoTriggerOnSpacePattern = ~/(\b(import|using|extends|implements|case|new|cast|override)|(->)) $/;
    function isInvalidCompletionPosition(params:CompletionParams, text:String):Bool {
        return switch (params.context.triggerCharacter) {
            case "$" if (!context.haxeServer.supportsJsonRpc): true;
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
        if (!context.haxeServer.capabilities.completionResolveProvider || previousCompletion == null || data.origin == Custom) {
            return resolve(item);
        }
        var importPosition = ImportHelper.getImportPosition(previousCompletion.doc);
        context.callHaxeMethod(DisplayMethods.CompletionItemResolve, {index: item.data.index}, token, result -> {
            resolve(createCompletionItem(result.item, previousCompletion.doc, previousCompletion.replaceRange, importPosition, previousCompletion.kind));
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
            previousCompletion = {
                doc: doc,
                kind: result.mode.kind,
                replaceRange: result.replaceRange
            };
            var items = [];
            var counter = 0;
            var importPosition = ImportHelper.getImportPosition(doc);
            for (i in 0...result.items.length) {
                var item = result.items[i];
                var completionItem = createCompletionItem(item, doc, result.replaceRange, importPosition, result.mode.kind);
                if (completionItem == null) {
                    continue;
                }
                completionItem.data = {origin: Haxe, index: i};
                completionItem.sortText = StringTools.lpad(Std.string(counter++), "0", 10);
                items.push(completionItem);
            };
            items = items.concat(postfixCompletion.createItems(result.mode, params.position, doc));
            items = items.concat(expectedTypeCompletion.createItems(result.mode, params.position, textBefore));
            resolve(items);
            return items.length + " items";
        }, error -> reject(ResponseError.internalError(error)));
    }

    function createCompletionItem<T>(item:HaxeCompletionItem<T>, doc:TextDocument, replaceRange:Range, importPosition:Position, mode:CompletionModeKind<Dynamic>):CompletionItem {
        var label = "";
        var kind = null;
        var type = null;

        switch (item.kind) {
            case Local:
                label = item.args.name;
                kind = Variable;
                type = item.args.type;

            case ClassField | EnumAbstractValue:
                return createClassFieldCompletionItem(item.args, item.kind, replaceRange, mode);

            case EnumValue:
                return createEnumValueCompletionItem(item.args.field, replaceRange, mode);

            case Type:
                return createTypeCompletionItem(item.args, doc, replaceRange, importPosition, mode);

            case Package:
                return createPackageCompletionItem(item.args, replaceRange, mode);

            case Module:
                label = cast item.args;
                kind = Folder;

            case Literal:
                label = item.args.name;
                kind = Keyword;
                type = item.args.type;

            case Metadata:
                label = item.args.name;
                kind = Function;

            case Keyword:
                return createKeywordCompletionItem(item.args, replaceRange, mode);

            case AnonymousStructure:
            case Expression:
                // these never appear as completion items right now
        }

        var result:CompletionItem = {label: label};
        if (kind != null) {
            result.kind = kind;
        }
        if (type != null) {
            result.detail = printer.printType(type);
            if (commitCharactersSupport && type.kind == TFun) {
                result.commitCharacters = ["("];
            }
        }
        var documentation = item.getDocumentation();
        if (documentation != null) {
            result.documentation = formatDocumentation(documentation);
        }
        if (replaceRange != null) {
            result.textEdit = {range: replaceRange, newText: label};
        }
        return result;
    }

    function createClassFieldCompletionItem<T>(usage:ClassFieldUsage<T>, kind:HaxeCompletionItemKind<Dynamic>, replaceRange:Range, mode:CompletionModeKind<Dynamic>):CompletionItem {
        var field = usage.field;
        var item:CompletionItem = {
            label: field.name,
            kind: getKindForField(field, kind),
            detail: {
                var overloads = if (usage.field.overloads == null) 0 else usage.field.overloads.length;
                var type = printer.printType(field.type);
                if (overloads > 0) {
                    type += ' (+$overloads overloads)';
                }
                type + printClassFieldOrigin(usage.origin, kind);
            },
            documentation: formatDocumentation(field.doc),
            textEdit: {
                newText: switch (mode) {
                    case StructureField: field.name + ": ";
                    case Pattern: field.name + ":";
                    case Override if (field.type.kind == TFun): printer.printEmptyFunctionDefinition(field);
                    case _: field.name;
                },
                range: replaceRange
            }
        }

        if (commitCharactersSupport && field.type.kind == TFun) {
            item.commitCharacters = ["("];
        }

        return item;
    }

    function getKindForField<T>(field:JsonClassField, kind:HaxeCompletionItemKind<Dynamic>):CompletionItemKind {
        function hasOperatorMeta(meta:JsonMetadata) {
            return meta.exists(meta -> meta.name == ":op" || meta.name == ":resolve" || meta.name == ":arrayAccess");
        }
        var fieldKind:JsonFieldKind<T> = field.kind;
        return switch (fieldKind.kind) {
            case FVar:
                var read = fieldKind.args.read.kind;
                var write = fieldKind.args.write.kind;
                switch [read, write] {
                    case [AccNormal, AccNormal]: Field;
                    case [AccNormal, AccCtor]: Field; // final
                    case [AccNormal, AccNever]: Field; // static final
                    case [AccInline, _] if (kind == EnumAbstractValue): EnumMember;
                    case [AccInline, _]: Constant;
                    case _: Property;
                }
            case FMethod if (hasOperatorMeta(field.meta)): Operator;
            case FMethod if (field.scope == Static): Function;
            case FMethod if (field.scope == Constructor): Constructor;
            case FMethod: Method;
        }
    }

    function printClassFieldOrigin<T>(origin:ClassFieldOrigin<T>, kind:HaxeCompletionItemKind<Dynamic>):String {
        if (kind == EnumAbstractValue) {
            return "";
        }
        if (origin.args == null && origin.kind != cast BuiltIn) {
            return "";
        }
        return "\nfrom " + switch (origin.kind) {
            case Self:
                '\'${origin.args.name}\'';
            case Parent:
                'parent type \'${origin.args.name}\'';
            case StaticExtension:
                '\'${origin.args.name}\' (static extension method)';
            case StaticImport:
                'static import';
            case AnonymousStructure:
                'anonymous structure';
            case BuiltIn:
                'compiler (built-in)';
        };
    }

    function getKindForType<T>(type:JsonType<T>):CompletionItemKind {
        return switch (type.kind) {
            case TFun: Function;
            case _: Field;
        }
    }

    function createEnumValueCompletionItem(enumValue:JsonEnumField, replaceRange:Range, mode:CompletionModeKind<Dynamic>):CompletionItem {
        var name = enumValue.name;
        var type = enumValue.type;

        var item:CompletionItem = {
            label: name,
            kind: EnumMember,
            detail: printer.printType(type),
            documentation: formatDocumentation(enumValue.doc),
            textEdit: {
                newText: name,
                range: replaceRange
            }
        };

        if (mode != Pattern) {
            return item;
        }

        switch (type.kind) {
            case TEnum:
                item.textEdit.newText = name + ":";
            case TFun if (snippetSupport):
                var signature:JsonFunctionSignature = type.args;
                var text = '$name(';
                for (i in 0...signature.args.length) {
                    var arg = signature.args[i];
                    text += '$${${i+1}:${arg.name}}';
                    if (i < signature.args.length - 1) {
                        text += ", ";
                    }
                }
                text += "):";
                item.insertTextFormat = Snippet;
                item.textEdit.newText = text;
            case _:
        }
        return item;
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

        var item:CompletionItem = {
            label: qualifiedName,
            kind: getKindForModuleType(type),
            documentation: formatDocumentation(type.doc),
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
                    item.label = unqualifiedName;
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

        if (commitCharactersSupport && mode == New) {
            item.commitCharacters = ["("];
        }

        if (type.params != null) {
            item.detail = printTypeDetail(type);
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
            case TypeAlias | ImportAlias: Interface;
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

    function printTypeDetail(type:ModuleType):String {
        var detail = printer.printTypeDeclaration(type) + "\n";
        switch (type.importStatus) {
            case Imported:
                detail += "(imported)";
            case Unimported:
                var containerName = printer.printQualifiedTypePath(type).untilLastDot();
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

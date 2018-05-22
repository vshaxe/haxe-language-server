package haxeLanguageServer.features;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import haxeLanguageServer.server.Protocol;
import haxeLanguageServer.server.Protocol.CompletionItem as HaxeCompletionItem;
import haxeLanguageServer.server.Protocol.CompletionItemKind as HaxeCompletionItemKind;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.helper.ImportHelper;
import haxeLanguageServer.helper.TypePrinter;
import languageServerProtocol.protocol.Protocol.CompletionParams;
import languageServerProtocol.Types.CompletionItem;
import languageServerProtocol.Types.CompletionItemKind;
import haxe.display.JsonModuleTypes;
import haxe.extern.EitherType;
using Lambda;

private typedef PreviousCompletionResult = {
    var doc:TextDocument;
    var replaceRange:Range;
    var kind:CompletionResultKind;
}

class CompletionFeature {
    final context:Context;
    final legacy:CompletionFeatureLegacy;
    final printer:TypePrinter;
    final triggerSuggest:Command;
    final triggerParameterHints:Command;

    var previousCompletion:PreviousCompletionResult;
    var contextSupport:Bool;
    var markdownSupport:Bool;
    var snippetSupport:Bool;

    public function new(context) {
        this.context = context;
        checkCapabilities();
        legacy = new CompletionFeatureLegacy(context, contextSupport, formatDocumentation);
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
        if (!context.haxeServer.capabilities.completionResolveProvider || previousCompletion == null) {
            return resolve(item);
        }
        var importPosition = ImportHelper.getImportPosition(previousCompletion.doc);
        context.callHaxeMethod(HaxeMethods.CompletionItemResolve, {index: item.data.index}, token, result -> {
            resolve(createCompletionItem(result.item, previousCompletion.doc, previousCompletion.replaceRange, importPosition, previousCompletion.kind));
            return null;
        }, error -> {
            reject(ResponseError.internalError(error));
        });
    }

    function handleJsonRpc(params:CompletionParams, token:CancellationToken, resolve:Array<CompletionItem>->Void, reject:ResponseError<NoData>->Void, doc:TextDocument, offset:Int, textBefore:String) {
        var wasAutoTriggered = params.context == null ? true : params.context.triggerKind == TriggerCharacter;
        var params = {
            file: doc.fsPath,
            contents: doc.content,
            offset: offset,
            wasAutoTriggered: wasAutoTriggered,
        };
        context.callHaxeMethod(HaxeMethods.Completion, params, token, result -> {
            if (result.kind != TypeHint && wasAutoTriggered && isAfterArrow(textBefore)) {
                resolve([]); // avoid auto-popup after -> in arrow functions
                return null;
            }
            previousCompletion = {
                doc: doc,
                kind: result.kind,
                replaceRange: result.replaceRange
            };
            var items = [];
            var counter = 0;
            var importPosition = ImportHelper.getImportPosition(doc);
            for (i in 0...result.items.length) {
                var item = result.items[i];
                var completionItem = createCompletionItem(item, doc, result.replaceRange, importPosition, result.kind);
                if (completionItem == null) {
                    continue;
                }
                completionItem.data = {index: i};
                if (result.sorted) {
                    completionItem.sortText = StringTools.lpad(Std.string(counter++), "0", 10);
                }
                items.push(completionItem);
            };
            resolve(items);
            return items.length + " items";
        }, error -> reject(ResponseError.internalError(error)));
    }

    function createCompletionItem<T>(item:HaxeCompletionItem<T>, doc:TextDocument, replaceRange:Range, importPosition:Position, resultKind:CompletionResultKind):CompletionItem {
        var label = "";
        var kind = null;
        var type = null;

        switch (item.kind) {
            case Local:
                label = item.args.name;
                kind = Variable;
                type = item.args.type;

            case ClassField | EnumAbstractField:
                // TODO: merge these kinds together with some isEnumAbstractField flag?
                // actually, ClassFieldOrigin might solve that anyway...
                return createClassFieldCompletionItem(item.args, item.kind, replaceRange, resultKind);

            case EnumField:
                return createEnumFieldCompletionItem(item.args, replaceRange, resultKind);

            case Type:
                return createTypeCompletionItem(item.args, doc, replaceRange, importPosition, resultKind);

            case Package:
                return createPackageCompletionItem(item.args, replaceRange);

            case Module:
                label = item.args;
                kind = Class;

            case Literal:
                label = item.args.name;
                kind = Keyword;
                type = item.args.type;

            case Metadata:
                label = item.args.name;
                kind = Function;

            case Keyword:
                return createKeywordCompletionItem(item.args, replaceRange, resultKind);
        }

        var result:CompletionItem = {label: label};
        if (kind != null) {
            result.kind = kind;
        }
        if (type != null) {
            result.detail = printer.printType(type);
        }
        var documentation = getDocumentation(item);
        if (documentation != null) {
            result.documentation = formatDocumentation(documentation);
        }
        if (replaceRange != null) {
            result.textEdit = {range: replaceRange, newText: label};
        }
        return result;
    }

    function createClassFieldCompletionItem(field:JsonClassField, kind:HaxeCompletionItemKind<JsonClassField>, replaceRange:Range, resultKind:CompletionResultKind):CompletionItem {
        return {
            label: field.name,
            kind: getKindForField(field, kind),
            detail: printer.printType(field.type),
            textEdit: {
                newText: switch (resultKind) {
                    case StructureField: field.name + ": ";
                    case Pattern: field.name + ":";
                    case Override: printer.printEmptyFunctionDefinition(field);
                    case _: field.name;
                },
                range: replaceRange
            }
        };
    }

    function getKindForField<T>(field:JsonClassField, kind:HaxeCompletionItemKind<JsonClassField>):CompletionItemKind {
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
            case FMethod if (hasOperatorMeta(field.meta)): Operator;
            case FMethod if (field.scope == Static): Function;
            case FMethod if (field.scope == Constructor): Constructor;
            case FMethod: Method;
        }
    }

    function hasOperatorMeta(meta:JsonMetadata) {
        return meta.exists(meta -> meta.name == ":op" || meta.name == ":resolve" || meta.name == ":arrayAccess");
    }

    function getKindForType<T>(type:JsonType<T>):CompletionItemKind {
        return switch (type.kind) {
            case TFun: Function;
            case _: Field;
        }
    }

    function createEnumFieldCompletionItem(enumField:JsonEnumField, replaceRange:Range, resultKind:CompletionResultKind):CompletionItem {
        var name = enumField.name;
        var type = enumField.type;

        var item:CompletionItem = {
            label: name,
            kind: EnumMember,
            detail: printer.printType(type),
            documentation: formatDocumentation(enumField.doc),
            textEdit: {
                newText: name,
                range: replaceRange
            }
        };

        if (resultKind != Pattern) {
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

    function createTypeCompletionItem(type:ModuleType, doc:TextDocument, replaceRange:Range, importPosition:Position, resultKind:CompletionResultKind):CompletionItem {
        if (type.isPrivate) {
            return null; // TODO: show private types from the current module
        }

        var isImportCompletion = resultKind == Import || resultKind == Using;
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

        switch (resultKind) {
            case New if (snippetSupport):
                item.textEdit.newText += "($1)";
                item.insertTextFormat = Snippet;
                item.command = triggerParameterHints;
            case TypeHint if (snippetSupport && type.params != null && type.params.length > 0):
                item.textEdit.newText += "<$1>";
                item.insertTextFormat = Snippet;
            case StructExtension:
                item.textEdit.newText += ",";
            case _:
        }

        if (type.doc != null) {
            item.documentation = formatDocumentation(type.doc);
        }
        if (type.params != null) {
            item.detail = printTypeDetail(type);
        }

        return item;
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
        if (markdownSupport) {
            return {
                kind: MarkupKind.MarkDown,
                value: DocHelper.markdownFormat(doc)
            };
        }
        return DocHelper.extractText(doc);
    }

    function getDocumentation<T>(item:HaxeCompletionItem<T>):JsonDoc {
        return switch (item.kind) {
            case ClassField | EnumAbstractField: item.args.doc;
            case EnumField: item.args.doc;
            case Type: item.args.doc;
            case Metadata: item.args.doc;
            case _: null;
        }
    }

    function printTypeDetail(type:ModuleType):String {
        var detail = printer.printTypeDeclaration(type);
        switch (type.importStatus) {
            case Imported:
                detail += "\n(imported)";
            case Unimported:
                var containerName = printer.printQualifiedTypePath(type).untilLastDot();
                detail = "Auto-import from '" + containerName + "'\n" + detail;
            case Shadowed:
                detail += "\n(shadowed)";
        }
        return detail;
    }

    function createPackageCompletionItem(pack:String, replaceRange:Range):CompletionItem {
        return {
            label: pack,
            kind: Module,
            textEdit: {
                newText: pack + ".",
                range: replaceRange
            },
            command: triggerSuggest
        };
    }

    function createKeywordCompletionItem(keyword:Keyword, replaceRange:Range, resultKind:CompletionResultKind):CompletionItem {
        var item:CompletionItem = {
            label: keyword.name,
            kind: Keyword,
            textEdit: {
                newText: keyword.name,
                range: replaceRange
            }
        }

        if (resultKind == TypeRelation) {
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

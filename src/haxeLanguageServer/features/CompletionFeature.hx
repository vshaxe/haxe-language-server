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

class CompletionFeature {
    final context:Context;
    final legacy:CompletionFeatureLegacy;
    final printer:TypePrinter;
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

    static final autoTriggerOnSpacePattern = ~/\b(import|using|extends|implements|case|new|cast) $/;
    function isInvalidCompletionPosition(params:CompletionParams, text:String):Bool {
        if (params.context.triggerCharacter == "$" && !context.haxeServer.supportsJsonRpc) {
            return true;
        }
        return params.context.triggerCharacter == " " && !autoTriggerOnSpacePattern.match(text);
    }

    function handleJsonRpc(params:CompletionParams, token:CancellationToken, resolve:Array<CompletionItem>->Void, reject:ResponseError<NoData>->Void, doc:TextDocument, offset:Int, _) {
        var wasAutoTriggered = params.context == null ? true : params.context.triggerKind == TriggerCharacter;
        var params = {
            file: doc.fsPath,
            contents: doc.content,
            offset: offset,
            wasAutoTriggered: wasAutoTriggered,
        };
        context.callHaxeMethod(HaxeMethods.Completion, params, token, result -> {
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
        var newText = null;

        switch (item.kind) {
            case Local:
                label = item.args.name;
                kind = Variable;
                type = item.args.type;

            case ClassField | EnumAbstractField:
                label = item.args.name;
                kind = getKindForField(label, item.kind, item.args);
                type = item.args.type;
                switch (resultKind) {
                    case StructureField: newText = label + ": ";
                    case Pattern: newText = label + ":";
                    case _:
                }
                // TODO: merge these kinds together with some isStatic / isEnumAbstractField flags?

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
                label = item.args.name;
                kind = Keyword;
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
        if (replaceRange != null || newText != null) {
            if (newText == null) {
                newText = label;
            }
            result.textEdit = {range: replaceRange, newText: newText};
        }
        return result;
    }

    function getKindForField<T>(name:String, kind:HaxeCompletionItemKind<JsonClassField>, field:JsonClassField):CompletionItemKind {
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
            case FMethod if (name == "new"): Constructor;
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
            },
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

        var qualifiedName = printTypePath(type); // pack.Foo | pack.Foo.SubType
        var unqualifiedName = type.name; // Foo | SubType

        var item:CompletionItem = {
            label: qualifiedName,
            kind: getKindForModuleType(type),
            textEdit: {
                range: replaceRange,
                newText: if (autoImport) unqualifiedName else qualifiedName
            }
        };

        if (type.doc != null) {
            item.documentation = formatDocumentation(type.doc);
        }

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

        if (type.params != null) {
            item.detail = printTypeDetail(type);
        }

        switch (resultKind) {
            case New if (snippetSupport):
                item.textEdit.newText += "($1)";
                item.insertTextFormat = Snippet;
            case StructExtension:
                item.textEdit.newText += ",";
            case _:
        }

        return item;
    }

    function printTypePath(type:ModuleType):String {
        var result = type.pack.join(".");
        if (type.pack.length > 0) {
            result += ".";
        }
        result += type.moduleName;
        if (type.name != type.moduleName) {
            result += "." + type.name;
        }
        return result;
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

    function onCompletionItemResolve(item:CompletionItem, token:CancellationToken, resolve:CompletionItem->Void, reject:ResponseError<NoData>->Void) {
        if (!context.haxeServer.capabilities.completionResolveProvider) {
            return resolve(item);
        }
        context.callHaxeMethod(HaxeMethods.CompletionItemResolve, {index: item.data.index}, token, result -> {
            var detail = getDetail(result.item);
            if (detail != null) {
                item.detail = detail;
            }
            var documentation = getDocumentation(result.item);
            if (documentation != null) {
                item.documentation = formatDocumentation(documentation);
            }
            resolve(item);
            return null;
        }, error -> {
            reject(ResponseError.internalError(error));
        });
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

    function getDetail<T>(item:HaxeCompletionItem<T>):String {
        return switch (item.kind) {
            case Type: printTypeDetail(item.args);
            case _: null;
        }
    }

    function printTypeDetail(type:ModuleType):String {
        var detail = printTypeDeclaration(type);
        switch (type.importStatus) {
            case Imported:
                detail += "\n(imported)";
            case Unimported:
                var containerName = printTypePath(type).untilLastDot();
                detail = "Auto-import from '" + containerName + "'\n" + detail;
            case Shadowed:
                detail += "\n(shadowed)";
        }
        return detail;
    }

    /**
        Prints a type declaration in the form of `extern interface ArrayAccess<T>`.
        (`modifiers... keyword Name<Params>`)
    **/
    function printTypeDeclaration(type:ModuleType):String {
        var components = [];
        if (type.isPrivate) components.push("private");
        if (type.meta.exists(meta -> meta.name == ":final")) components.push("final");
        if (type.isExtern) components.push("extern");
        components.push(switch (type.kind) {
            case Class: "class";
            case Interface: "interface";
            case Enum: "enum";
            case Abstract: "abstract";
            case EnumAbstract: "enum abstract";
            case TypeAlias | Struct: "typedef";
        });
        var typeName = type.name;
        if (type.params.length > 0) {
            typeName += "<" + type.params.map(param -> param.name).join(", ") + ">";
        }
        components.push(typeName);
        return components.join(" ");
    }

    function createPackageCompletionItem(pack:String, replaceRange:Range):CompletionItem {
        return {
            label: pack,
            kind: Module,
            textEdit: {
                newText: pack + ".",
                range: replaceRange
            },
            command: {
                title: "Trigger Suggest",
                command: "editor.action.triggerSuggest"
            }
        };
    }
}

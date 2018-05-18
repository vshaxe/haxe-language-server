package haxeLanguageServer.features;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import haxeLanguageServer.server.Protocol;
import haxeLanguageServer.server.Protocol.CompletionItem as HaxeCompletionItem;
import haxeLanguageServer.server.Protocol.CompletionItemKind as HaxeCompletionItemKind;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.helper.ImportHelper;
import languageServerProtocol.protocol.Protocol.CompletionParams;
import languageServerProtocol.Types.CompletionItem;
import languageServerProtocol.Types.CompletionItemKind;
import haxe.display.JsonModuleTypes;
import haxe.display.JsonModuleTypesPrinter;
import haxe.extern.EitherType;
using Lambda;

class CompletionFeature {
    final context:Context;
    final legacy:CompletionFeatureLegacy;
    final printer:JsonModuleTypesPrinter;
    var contextSupport:Bool;
    var markdownSupport:Bool;
    var snippetSupport:Bool;

    public function new(context) {
        this.context = context;
        checkCapabilities();
        legacy = new CompletionFeatureLegacy(context, contextSupport, formatDocumentation);
        printer = new JsonModuleTypesPrinter();
        context.protocol.onRequest(Methods.Completion, onCompletion);
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
        if (contextSupport && isInvalidCompletionPosition(params.context, textBefore)) {
            return resolve([]);
        }
        var handle = if (context.haxeServer.capabilities.completionProvider) handleJsonRpc else legacy.handle;
        handle(params, token, resolve, reject, doc, offset, textBefore);
    }

    static final autoTriggerOnSpacePattern = ~/\b(import|using|extends|implements|case|new|cast) $/;
    function isInvalidCompletionPosition(context:CompletionContext, text:String):Bool {
        return context.triggerCharacter == " " && !autoTriggerOnSpacePattern.match(text);
    }

    function handleJsonRpc(params:CompletionParams, token:CancellationToken, resolve:Array<CompletionItem>->Void, reject:ResponseError<NoData>->Void, doc:TextDocument, offset:Int, _) {
        var wasAutoTriggered = params.context == null ? true : params.context.triggerKind == TriggerCharacter;
        context.callHaxeMethod(HaxeMethods.Completion, {file: doc.fsPath, offset: offset, wasAutoTriggered: wasAutoTriggered}, doc.content, token, result -> {
            var items = [];
            var counter = 0;
            var importPosition = ImportHelper.getImportPosition(doc);
            for (item in result.items) {
                var completionItem = createCompletionItem(item, doc, result.replaceRange, importPosition, result.kind);
                if (completionItem == null) {
                    continue;
                }
                if (result.sorted) {
                    completionItem.sortText = StringTools.lpad(Std.string(counter++), "0", 10);
                }
                items.push(completionItem);
            };
            resolve(items);
        }, error -> reject(ResponseError.internalError(error)));
    }

    function createCompletionItem<T>(item:HaxeCompletionItem<T>, doc:TextDocument, replaceRange:Range, importPosition:Position, resultKind:CompletionResultKind):CompletionItem {
        var label = "";
        var kind = CompletionItemKind.Variable;
        var type = null;

        switch (item.kind) {
            case Local:
                // TODO: define TVar

            case Member | Static | EnumAbstractField:
                label = item.args.name;
                kind = getKindForField(label, item.kind, item.args);
                type = item.args.type;

            case EnumField:
                label = item.args.name;
                kind = EnumMember;
                type = item.args.type;

            case Global:
                label = item.args.name;
                kind = getKindForType(item.args.type);
                type = item.args.type;

            case Type:
                return createTypeCompletionItem(item.args, doc, replaceRange, importPosition, resultKind);

            case Package:
                label = item.args;
                kind = Module;

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

        var item:CompletionItem = {
            label: label,
            kind: kind
        };
        if (type != null) {
            item.detail = printer.printType(type);
        }
        if (replaceRange != null) {
            item.textEdit = {range: replaceRange, newText: label};
        }
        return item;
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
            case FMethod if (kind == Static): Function;
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
        var containerName = qualifiedName.untilLastDot(); // pack | pack.Foo

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
                    item.detail = "(imported)";
                case Unimported:
                    var edit = ImportHelper.createImportEdit(doc, importPosition, qualifiedName, importConfig.style);
                    item.additionalTextEdits = [edit];
                    item.detail = "Auto-import from " + containerName;
                case Shadowed:
                    item.detail = "(shadowed)";
            }
        }

        if (resultKind == New && snippetSupport) {
            item.textEdit.newText += "($1)";
            item.insertTextFormat = Snippet;
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
}

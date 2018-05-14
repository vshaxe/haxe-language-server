package haxeLanguageServer.features;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import haxeLanguageServer.server.Protocol;
import haxeLanguageServer.server.Protocol.CompletionItem as HaxeCompletionItem;
import haxeLanguageServer.server.Protocol.CompletionItemKind as HaxeCompletionItemKind;
import languageServerProtocol.protocol.Protocol.CompletionParams;
import languageServerProtocol.Types.CompletionItem;
import languageServerProtocol.Types.CompletionItemKind;
import haxe.rtti.JsonModuleTypes;
using Lambda;

class CompletionFeature {
    final context:Context;
    final legacy:CompletionFeatureLegacy;
    var contextSupport:Bool;
    var markdownSupport:Bool;

    public function new(context) {
        this.context = context;
        checkCapabilities();
        legacy = new CompletionFeatureLegacy(context, contextSupport, markdownSupport);
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
        if (documentationFormat == null) return;

        markdownSupport = documentationFormat.indexOf(MarkDown) != -1;
    }

    function onCompletion(params:CompletionParams, token:CancellationToken, resolve:Array<CompletionItem>->Void, reject:ResponseError<NoData>->Void) {
        var doc = context.documents.get(params.textDocument.uri);
        var handle = if (context.haxeServer.capabilities.completionProvider) handleJsonRpc else legacy.handle;
        handle(params, token, resolve, reject, doc);
    }

    function handleJsonRpc(params:CompletionParams, token:CancellationToken, resolve:Array<CompletionItem>->Void, reject:ResponseError<NoData>->Void, doc:TextDocument) {
        var offset = doc.offsetAt(params.position);
        var wasAutoTriggered = params.context == null ? true : params.context.triggerKind == TriggerCharacter;
        context.callHaxeMethod(HaxeMethods.Completion, {file: doc.fsPath, offset: offset, wasAutoTriggered: wasAutoTriggered}, doc.content, token, result -> {
            var items = [];
            var counter = 0;
            for (item in result.items) {
                var completionItem = createCompletionItem(item);
                if (result.sorted) {
                    completionItem.sortText = "_" + counter++;
                }
                if (result.replaceRange != null) {
                    completionItem.textEdit = {
                        range: result.replaceRange,
                        newText: completionItem.label
                    }
                }
                items.push(completionItem);
            };
            resolve(items);
        }, error -> reject(ResponseError.internalError(error)));
    }

    function createCompletionItem<T>(item:HaxeCompletionItem<T>):CompletionItem {
        var label = "";
        var kind = CompletionItemKind.Variable;

        switch (item.kind) {
            case Local:
                // TODO: define TVar

            case Member | Static | EnumAbstractField:
                label = item.args.name;
                kind = getKindForField(label, item.kind, item.args);

            case EnumField:
                label = item.args.name;
                kind = EnumMember;

            case Global:
                label = item.args.name;
                kind = getKindForType(item.args.type);

            case Type:
                label = item.args.name;
                kind = getKindForModuleType(item.args);

            case Package:
                label = item.args;
                kind = Module;

            case Module:
                label = item.args;
                kind = Class;

            case Literal:
                label = Std.string(item.args);
                kind = Keyword;

            case Metadata:
                label = item.args.name;
                kind = Function;
        }

        return {
            label: label,
            kind: kind
        };
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

    function getKindForModuleType<T>(type:JsonModuleType<T>):CompletionItemKind {
        inline function typed<T>(type:JsonType<T>) return type;
        return switch (type.kind) {
            case Class if (type.args.isInterface): Interface;
            case Abstract if (type.meta.exists(meta -> meta.name == ":enum")): Enum;
            case Typedef if (typed(type.args.type).kind == TAnonymous): Struct;
            case Typedef: Interface;
            case Enum: Enum;
            case _: Class;
        }
    }
}

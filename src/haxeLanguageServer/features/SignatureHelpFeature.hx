package haxeLanguageServer.features;

import haxe.rtti.JsonModuleTypes.JsonFunctionArgument;
import haxeLanguageServer.helper.ArgumentNameHelper.addNamesToSignatureType;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.server.Protocol.HaxeMethods;
import haxeLanguageServer.server.Protocol.SignatureItem as HaxeSignatureItem;
import haxeLanguageServer.server.Protocol.SignatureInformation as HaxeSignatureInformation;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

typedef CurrentSignature = {
    var help(default, never):SignatureHelp;
    var params(default, never):TextDocumentPositionParams;
}

class SignatureHelpFeature {
    public var currentSignature(default, null):CurrentSignature;
    final context:Context;

    public function new(context:Context) {
        this.context = context;
        context.protocol.onRequest(Methods.SignatureHelp, onSignatureHelp);
    }

    function onSignatureHelp(params:TextDocumentPositionParams, token:CancellationToken, resolve:SignatureHelp->Void, reject:ResponseError<NoData>->Void) {
        var doc = context.documents.get(params.textDocument.uri);
        var handle = if (context.haxeServer.capabilities.signatureHelpProvider) handleJsonRpc else handleLegacy;
        handle(params, token, resolve, reject, doc);
    }

    function handleJsonRpc(params:TextDocumentPositionParams, token:CancellationToken, resolve:SignatureHelp->Void, reject:ResponseError<NoData>->Void, doc:TextDocument) {
        var wasAutoTriggered = true; // TODO: doesn't seem to be in the API?
        context.callHaxeMethod(HaxeMethods.SignatureHelp, {file: doc.fsPath, offset: doc.offsetAt(params.position), wasAutoTriggered: wasAutoTriggered}, doc.content, token, result -> {
            resolve(createSignatureHelp(result));
        }, error -> reject(ResponseError.internalError(error)));
    }

    function createSignatureHelp(item:HaxeSignatureItem):SignatureHelp {
        var printer = new haxe.rtti.JsonModuleTypesPrinter();
        function createSignatureParameter(arg:JsonFunctionArgument):ParameterInformation {
            return {
                label: printer.printFunctionArgument(arg)
            }
        }
        function createSignatureInformation(info:HaxeSignatureInformation):SignatureInformation {
            return {
                label: printer.printType({kind: TFun, args: {args: info.args, ret: info.ret}}),
                documentation: {
                    kind: MarkupKind.MarkDown,
                    value: DocHelper.markdownFormat(info.documentation)
                },
                parameters: info.args.map(createSignatureParameter)
            }
        }
        return {
            activeSignature: item.activeSignature,
            activeParameter: item.activeParameter,
            signatures: item.signatures.map(createSignatureInformation)
        };
    }

    function handleLegacy(params:TextDocumentPositionParams, token:CancellationToken, resolve:SignatureHelp->Void, reject:ResponseError<NoData>->Void, doc:TextDocument) {
        var bytePos = context.displayOffsetConverter.characterOffsetToByteOffset(doc.content, doc.offsetAt(params.position));
        var args = ['${doc.fsPath}@$bytePos@signature'];
        context.callDisplay(args, doc.content, token, function(r) {
            switch (r) {
                case DCancelled:
                    resolve(null);
                case DResult(data):
                    var help:SignatureHelp = haxe.Json.parse(data);
                    for (signature in help.signatures) {
                        signature.documentation = {
                            kind: MarkupKind.MarkDown,
                            value: DocHelper.markdownFormat(signature.documentation)
                        };
                        var parameters = signature.parameters;
                        for (i in 0...signature.parameters.length)
                            parameters[i].label = addNamesToSignatureType(parameters[i].label, i);
                        signature.label = addNamesToSignatureType(signature.label);
                    }
                    resolve(help);

                    if (currentSignature != null) {
                        var oldDoc = context.documents.get(currentSignature.params.textDocument.uri);
                        oldDoc.removeUpdateListener(onUpdateTextDocument);
                    }
                    currentSignature = {help: help, params: params};
                    doc.addUpdateListener(onUpdateTextDocument);
            }
        }, function(error) reject(ResponseError.internalError(error)));
    }

    function onUpdateTextDocument(doc:TextDocument, events:Array<TextDocumentContentChangeEvent>, version:Int) {
        // if there's any non-whitespace changes, consider us not to be in the signature anymore
        // - otherwise, code actions might generate incorrect code
        inline function hasNonWhitespace(s:String)
            return s.trim().length > 0;

        for (event in events) {
            if (event.range == null)
                continue;

            if (event.range.start.isAfterOrEqual(event.range.end)) {
                if (hasNonWhitespace(event.text)) {
                    currentSignature = null;
                    break;
                }
            } else { // removing text
                var removedText = doc.getText(event.range);
                if (hasNonWhitespace(removedText)) {
                    currentSignature = null;
                    break;
                }
            }
        }
    }
}

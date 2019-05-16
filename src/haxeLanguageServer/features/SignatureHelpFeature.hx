package haxeLanguageServer.features;

import haxe.extern.EitherType;
import haxe.display.JsonModuleTypes.JsonFunctionArgument;
import haxeLanguageServer.helper.IdentifierHelper.addNamesToSignatureType;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.protocol.helper.DisplayPrinter;
import haxeLanguageServer.protocol.Display.DisplayMethods;
import haxeLanguageServer.protocol.Display.SignatureItem as HaxeSignatureItem;
import haxeLanguageServer.protocol.Display.SignatureInformation as HaxeSignatureInformation;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

class SignatureHelpFeature {
	final context:Context;

	public function new(context:Context) {
		this.context = context;
		context.languageServerProtocol.onRequest(Methods.SignatureHelp, onSignatureHelp);
	}

	function onSignatureHelp(params:TextDocumentPositionParams, token:CancellationToken, resolve:SignatureHelp->Void, reject:ResponseError<NoData>->Void) {
		var uri = params.textDocument.uri;
		var doc:Null<TextDocument> = context.documents.get(uri);
		if (doc == null) {
			return reject.documentNotFound(uri);
		}
		if (!uri.isFile()) {
			return reject.notAFile();
		}
		var handle = if (context.haxeServer.supports(DisplayMethods.SignatureHelp)) handleJsonRpc else handleLegacy;
		handle(params, token, resolve, reject, doc);
	}

	function handleJsonRpc(params:TextDocumentPositionParams, token:CancellationToken, resolve:SignatureHelp->Void, reject:ResponseError<NoData>->Void,
			doc:TextDocument) {
		var params = {
			file: doc.uri.toFsPath(),
			contents: doc.content,
			offset: doc.offsetAt(params.position),
			wasAutoTriggered: true // TODO: send this once the API supports it (https://github.com/Microsoft/vscode/issues/34737)
		}
		context.callHaxeMethod(DisplayMethods.SignatureHelp, params, token, result -> {
			resolve(createSignatureHelp(result));
			return null;
		}, reject.handler());
	}

	function createSignatureHelp(item:HaxeSignatureItem):SignatureHelp {
		var printer = new DisplayPrinter();
		function createSignatureParameter(arg:JsonFunctionArgument):ParameterInformation {
			return {
				label: printer.printFunctionArgument(arg)
			}
		}
		function createSignatureInformation(info:HaxeSignatureInformation):SignatureInformation {
			var label = if (item.kind == ArrayAccess) {
				printer.printArrayAccess(info);
			} else {
				printer.printType({kind: TFun, args: {args: info.args, ret: info.ret}});
			}
			return {
				label: label,
				documentation: getSignatureDocumentation(info.documentation),
				parameters: info.args.map(createSignatureParameter)
			};
		}
		return {
			activeSignature: item.activeSignature,
			activeParameter: item.activeParameter,
			signatures: item.signatures.map(createSignatureInformation),
		};
	}

	function handleLegacy(params:TextDocumentPositionParams, token:CancellationToken, resolve:SignatureHelp->Void, reject:ResponseError<NoData>->Void,
			doc:TextDocument) {
		var bytePos = context.displayOffsetConverter.characterOffsetToByteOffset(doc.content, doc.offsetAt(params.position));
		var args = ['${doc.uri.toFsPath()}@$bytePos@signature'];
		context.callDisplay("@signature", args, doc.content, token, function(r) {
			switch (r) {
				case DCancelled:
					resolve(null);
				case DResult(data):
					var help:SignatureHelp = haxe.Json.parse(data);
					for (signature in help.signatures) {
						signature.documentation = getSignatureDocumentation(signature.documentation);
						var parameters = signature.parameters;
						for (i in 0...signature.parameters.length)
							parameters[i].label = addNamesToSignatureType(parameters[i].label, i);
						signature.label = addNamesToSignatureType(signature.label);
					}
					resolve(help);
			}
		}, reject.handler());
	}

	function getSignatureDocumentation(documentation:String):Null<EitherType<String, MarkupContent>> {
		if (context.config.user.enableSignatureHelpDocumentation) {
			return {
				kind: MarkupKind.MarkDown,
				value: DocHelper.markdownFormat(documentation)
			};
		}
		return null;
	}
}

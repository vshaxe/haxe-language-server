package haxeLanguageServer.features.haxe;

import haxe.Json;
import haxe.display.Display.DisplayMethods;
import haxe.display.Display.SignatureInformation as HaxeSignatureInformation;
import haxe.display.Display.SignatureItem as HaxeSignatureItem;
import haxe.display.JsonModuleTypes.JsonFunctionArgument;
import haxe.extern.EitherType;
import haxeLanguageServer.features.haxe.codeAction.TokenTreeUtils;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.helper.IdentifierHelper.addNamesToSignatureType;
import haxeLanguageServer.helper.SemVer;
import haxeLanguageServer.protocol.DisplayPrinter;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.MarkupContent;
import languageServerProtocol.Types.MarkupKind;
import languageServerProtocol.Types.ParameterInformation;
import languageServerProtocol.Types.SignatureHelp;
import languageServerProtocol.Types.SignatureInformation;

class SignatureHelpFeature {
	final context:Context;
	final labelOffsetSupport:Bool;

	public function new(context:Context) {
		this.context = context;
		labelOffsetSupport = context.capabilities.textDocument?.signatureHelp?.signatureInformation?.parameterInformation?.labelOffsetSupport == true;
		context.languageServerProtocol.onRequest(SignatureHelpRequest.type, onSignatureHelp);
	}

	function onSignatureHelp(params:SignatureHelpParams, token:CancellationToken, resolve:Null<SignatureHelp>->Void, reject:ResponseError<NoData>->Void) {
		final uri = params.textDocument.uri;
		final doc:Null<HaxeDocument> = context.documents.getHaxe(uri);
		if (doc == null || !uri.isFile()) {
			return reject.noFittingDocument(uri);
		}
		final handle = if (context.haxeServer.supports(DisplayMethods.SignatureHelp)) handleJsonRpc else handleLegacy;
		handle(params, token, resolve, reject, doc);
	}

	function handleJsonRpc(params:SignatureHelpParams, cancellationToken:CancellationToken, resolve:Null<SignatureHelp>->Void,
			reject:ResponseError<NoData>->Void, doc:HaxeDocument) {
		var wasAutoTriggered = true;
		if (context.haxeServer.haxeVersion >= new SemVer(4, 1, 0)) {
			final triggerKind = params?.context?.triggerKind;
			wasAutoTriggered = switch triggerKind {
				case null: false; // err on the side of showing too often for LSP clients that don't support triggerKind
				case TriggerCharacter: true;
				case ContentChange | Invoked: false;
			}
		}

		/**
			close signature hint inside of callback argument scope:
			```haxe
			foo(0, |(name, age) -> {}|);
			```
		**/
		var token = doc.tokens?.getTokenAtOffset(doc.offsetAt(params.position));
		while (token != null) {
			final isCall = TokenTreeUtils.isCallPOpen(token);
			if (isCall) {
				break;
			}
			final isInFuction = TokenTreeUtils.isFunctionBrOpen(token);
			if (isInFuction) {
				resolve(null);
				return;
			}
			token = token.parent;
		}
		final params = {
			file: doc.uri.toFsPath(),
			contents: doc.content,
			offset: context.displayOffsetConverter.characterOffsetToByteOffset(doc.content, doc.offsetAt(params.position)),
			wasAutoTriggered: wasAutoTriggered
		}
		context.callHaxeMethod(DisplayMethods.SignatureHelp, params, cancellationToken, function(result) {
			if (result == null) {
				resolve(null);
			} else {
				resolve(createSignatureHelp(result));
			}
			return null;
		}, reject.handler());
	}

	function createSignatureHelp(item:HaxeSignatureItem):SignatureHelp {
		final printer = new DisplayPrinter();
		var labelOffset = 1; // ( or [
		function createSignatureParameter(arg:JsonFunctionArgument):ParameterInformation {
			return {
				label: {
					final printed = printer.printFunctionArgument(arg);
					if (labelOffsetSupport) {
						final range = [labelOffset, labelOffset + printed.length];
						labelOffset += printed.length;
						labelOffset += 2; // comma and space
						range;
					} else {
						printed;
					}
				}
			}
		}
		function createSignatureInformation(info:HaxeSignatureInformation):SignatureInformation {
			final label = if (item.kind == ArrayAccess) {
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
			signatures: (item.signatures ?? []).map(createSignatureInformation),
		};
	}

	function handleLegacy(params:SignatureHelpParams, token:CancellationToken, resolve:Null<SignatureHelp>->Void, reject:ResponseError<NoData>->Void,
			doc:HaxeDocument) {
		final bytePos = context.displayOffsetConverter.characterOffsetToByteOffset(doc.content, doc.offsetAt(params.position));
		final args = ['${doc.uri.toFsPath()}@$bytePos@signature'];
		context.callDisplay("@signature", args, doc.content, token, function(result) {
			switch result {
				case DCancelled:
					resolve(null);
				case DResult(data):
					final help:SignatureHelp = Json.parse(data);
					for (signature in help.signatures) {
						signature.documentation = getSignatureDocumentation(signature.documentation);
						final parameters = signature.parameters;
						if (parameters != null) {
							for (i in 0...parameters.length)
								parameters[i].label = addNamesToSignatureType(parameters[i].label, i);
						}
						signature.label = addNamesToSignatureType(signature.label);
					}
					resolve(help);
			}
		}, reject.handler());
	}

	function getSignatureDocumentation(documentation:Null<String>):Null<EitherType<String, MarkupContent>> {
		if (documentation != null && context.config.user.enableSignatureHelpDocumentation) {
			return {
				kind: MarkupKind.MarkDown,
				value: DocHelper.markdownFormat(documentation)
			};
		}
		return js.Lib.undefined;
	}
}

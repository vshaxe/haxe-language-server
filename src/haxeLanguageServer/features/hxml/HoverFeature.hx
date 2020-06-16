package haxeLanguageServer.features.hxml;

import haxeLanguageServer.features.hxml.HxmlContextAnalyzer.analyzeHxmlContext;
import haxeLanguageServer.helper.DocHelper.printCodeBlock;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

class HoverFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.languageServerProtocol.onRequest(HoverRequest.type, onHover);
	}

	public function onHover(params:TextDocumentPositionParams, token:CancellationToken, resolve:Null<Hover>->Void, reject:ResponseError<NoData>->Void) {
		final uri = params.textDocument.uri;
		final doc = context.documents.getHxml(uri);
		if (doc == null) {
			return reject.noFittingDocument(uri);
		}
		final pos = params.position;
		final line = doc.lineAt(pos.line);
		final hxmlContext = analyzeHxmlContext(line, pos);
		function makeHover(sections:Array<String>):Hover {
			return {
				contents: {
					kind: MarkDown,
					value: sections.join("\n\n---\n")
				},
				range: hxmlContext.range
			}
		}
		resolve(switch hxmlContext.element {
			case Flag(flag) if (flag != null):
				var signature = flag.name;
				if (flag.argument != null) {
					signature += " " + flag.argument.name;
				}
				makeHover([printCodeBlock(signature, Hxml), flag.description]);
			case EnumValue(value, _) if (value != null):
				makeHover([printCodeBlock(value.name, Hxml), value.description]);
			case Define(define) if (define != null):
				makeHover([printCodeBlock(define.getRealName(), Hxml), define.printDetails()]);
			case DefineValue(define, value): null;
			case _: null;
		});
	}
}

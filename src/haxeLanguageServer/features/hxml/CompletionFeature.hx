package haxeLanguageServer.features.hxml;

import haxeLanguageServer.features.hxml.HxmlFlags;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
using Lambda;
class CompletionFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
	}

	public function onCompletion(params:CompletionParams, token:CancellationToken, resolve:CompletionList->Void, reject:ResponseError<NoData>->Void) {
		final uri = params.textDocument.uri;
		final doc = context.documents.getHxml(params.textDocument.uri);
		if (doc == null) {
			reject.noFittingDocument(uri);
		}
		function complete(items:Array<CompletionItem>) {
			resolve({
				isIncomplete: false,
				items: items
			});
		}
		var pos = params.position;
		final line = doc.lineAt(pos.line);
		final textBefore = line.substring(0, pos.character);
		final wordPattern = ~/[-\w]+$/;
		if (wordPattern.match(textBefore)) {
			pos = pos.translate(0, -wordPattern.matched(0).length);
		}
		final parts = textBefore.trim().split(" ");
		if (parts.length > 1 || (parts.length == 1 && textBefore.last() == " ")) {
			// we're not completing the flag, but after it
			return complete([]);
		}
		complete(HxmlFlags.flatten().map(function(flag) {
			final item:CompletionItem = {
				label: flag.name,
				kind: Function,
				textEdit: {
					range: pos.toRange(),
					newText: flag.name
				},
				documentation: {
					kind: MarkDown,
					value: flag.description
				},
				insertTextFormat: Snippet
			}
			final arg = flag.argument;
			if (arg != null) {
				item.label += " " + arg.name;
				item.textEdit.newText += " ";
				if (arg.insertion != null) {
					var insertion = arg.insertion;
					if (!insertion.contains("$")) {
						insertion = '$${1:$insertion}';
					}
					item.textEdit.newText += insertion;
				}
			}
			return item;
		}));
	}
}

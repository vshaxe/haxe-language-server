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
		final pos = params.position;
		final line = doc.lineAt(pos.line);
		final textBefore = line.substring(0, pos.character);
		final wordPattern = ~/[-\w]+$/;
		final range = {start: pos, end: pos};
		if (wordPattern.match(textBefore)) {
			range.start = pos.translate(0, -wordPattern.matched(0).length);
		}
		final parts = ~/\s+/.replace(textBefore.ltrim(), " ").split(" ");
		resolve({
			isIncomplete: false,
			items: switch parts {
				case [] | [_]:
					createFlagCompletionItems(range);
				case [flag, _]:
					createArgumentCompletionItems(range, flag);
				case _:
					// no completion after the first argument
					[];
			}
		});
	}

	function createFlagCompletionItems(range:Range):Array<CompletionItem> {
		final items = [];
		function addFlag(flag:HxmlFlag) {
			final item:CompletionItem = {
				label: flag.name,
				kind: Function,
				textEdit: {
					range: range,
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
			items.push(item);
		}
		for (flag in HxmlFlags.flatten()) {
			addFlag(flag);
		}
		return items;
	}

	function createArgumentCompletionItems(range:Range, flag:String):Array<CompletionItem> {
		return [];
	}
}

package haxeLanguageServer.features.hxml;

import haxeLanguageServer.features.hxml.Defines;
import haxeLanguageServer.features.hxml.HxmlContextAnalyzer;
import haxeLanguageServer.features.hxml.HxmlFlags;
import haxeLanguageServer.helper.VscodeCommands;
import haxeLanguageServer.protocol.DisplayPrinter;
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
			return reject.noFittingDocument(uri);
		}
		final pos = params.position;
		final line = doc.lineAt(pos.line);
		final textBefore = line.substr(0, pos.character);
		final textAfter = line.substr(pos.character);
		final hxmlContext = analyzeHxmlContext(textBefore, pos);
		resolve({
			isIncomplete: false,
			items: switch hxmlContext.element {
				case Flag(_): createFlagCompletion(hxmlContext.range, textAfter);
				case EnumValue(_, values):
					[
						for (name => value in values)
							{
								label: name,
								kind: EnumMember,
								documentation: value.description
							}
					];
				case Define(): createDefineCompletion();
				case DefineValue(define, value):
					[
						{
							label: "value"
						}
					];
				case Unknown: [];
			}
		});
	}

	function createFlagCompletion(range:Range, textAfter:String):Array<CompletionItem> {
		final items = [];
		function addFlag(flag:HxmlFlag, name:String) {
			final item:CompletionItem = {
				label: name,
				filterText: name,
				kind: Function,
				textEdit: {
					range: range,
					newText: name
				},
				documentation: {
					kind: MarkDown,
					value: flag.description.capitalize() + "."
				},
				insertTextFormat: Snippet
			}
			final arg = flag.argument;
			if (arg != null) {
				item.label += " " + arg.name;
				trace(textAfter.charAt(0));
				if (textAfter.charAt(0) != " ") {
					item.textEdit.newText += " ";
				}
				if (arg.insertion != null) {
					var insertion = arg.insertion;
					if (!insertion.contains("$")) {
						insertion = '$${1:$insertion}';
					}
					item.textEdit.newText += insertion;
				}
				if (arg.kind != null) {
					item.command = TriggerSuggest;
				}
			}
			items.push(item);
		}
		for (flag in HxmlFlags.flatten()) {
			addFlag(flag, flag.name);
			if (flag.shortName != null) {
				addFlag(flag, flag.shortName);
			}
		}
		return items;
	}

	function createDefineCompletion():Array<CompletionItem> {
		final displayPrinter = new DisplayPrinter();
		return Defines.map(define -> {
			final name = define.define.replace("_", "-");
			final item:CompletionItem = {
				label: name,
				kind: Constant,
				documentation: {
					kind: MarkDown,
					value: displayPrinter.printMetadataDetails({
						name: name,
						doc: define.doc,
						links: cast define.links,
						platforms: cast define.platforms,
						parameters: cast define.params,
						targets: [],
						internal: false
					})
				}
			}
			if (define.params != null) {
				item.insertText = item.label + "=";
				item.command = TriggerSuggest;
			}
			return item;
		});
	}
}

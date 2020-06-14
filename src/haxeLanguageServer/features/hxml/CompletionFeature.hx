package haxeLanguageServer.features.hxml;

import haxeLanguageServer.features.hxml.Defines;
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
				case [] | [_]: createFlagCompletion(range);
				case [flag, arg]: createArgumentCompletion(range, flag, arg);
				case _: []; // no completion after the first argument
			}
		});
	}

	function createFlagCompletion(range:Range):Array<CompletionItem> {
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
				item.textEdit.newText += " ";
				if (arg.insertion != null) {
					var insertion = arg.insertion;
					if (!insertion.contains("$")) {
						insertion = '$${1:$insertion}';
					}
					item.textEdit.newText += insertion;
				}
				if (arg.completion != null) {
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

	function createArgumentCompletion(range:Range, flag:String, arg:String):Array<CompletionItem> {
		final flag = HxmlFlags.flatten().find(f -> f.name == flag || f.shortName == flag || f.deprecatedNames!.contains(flag));
		return switch flag!.argument!.completion {
			case null:
				[];
			case Enum(values):
				values.map(function(value):CompletionItem {
					return {
						label: value.name,
						kind: EnumMember,
						documentation: value.description
					}
				});
			case Define:
				switch arg.split("=") {
					case [] | [_]: createDefineCompletion(flag);
					case [define, _]: createDefineArgumentCompletion(define);
					case _: [];
				}
		}
	}

	function createDefineCompletion(flag:HxmlFlag):Array<CompletionItem> {
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

	function createDefineArgumentCompletion(define:String):Array<CompletionItem> {
		final define = Defines.find(d -> d.define == define);
		if (define == null) {
			return [];
		}
		return [];
	}
}

package haxeLanguageServer.features.completion;

import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.protocol.Display;

using haxe.io.Path;

class SnippetCompletion {
	public function new() {}

	public function createItems<T1, T2>(data:CompletionContextData, items:Array<DisplayItem<T1>>):Array<CompletionItem> {
		var isTypeLevel = false;
		for (item in items) {
			switch (item.kind) {
				case Keyword:
					var kwd:KeywordKind = item.args.name;
					if (kwd == Class) {
						isTypeLevel = true;
						break;
					}
				case _:
			}
		}

		if (isTypeLevel) {
			var moduleName = data.doc.uri.toFsPath().toString().withoutDirectory().withoutExtension();
			function makeType(item:{label:String, code:String}):CompletionItem {
				return {
					label: item.label + " " + moduleName,
					kind: Snippet,
					textEdit: {
						range: data.replaceRange,
						newText: item.code
					},
					insertTextFormat: Snippet,
					documentation: {
						kind: MarkDown,
						value: DocHelper.printCodeBlock(prettifySnippet(item.code), Haxe)
					}
				}
			}
			var name = '$${1:$moduleName}';
			var abstractName = name + '($${2:Type})';
			var body = '{\n\t$0\n}';
			return [
				{label: "class", code: 'class $name $body'},
				{label: "interface", code: 'interface $name $body'},
				{label: "enum", code: 'enum $name $body'},
				{label: "typedef", code: 'typedef $name = '},
				{label: "struct", code: 'typedef $name = $body'},
				{label: "abstract", code: 'abstract $abstractName $body'},
				{label: "enum abstract", code: 'enum abstract $abstractName $body'}
			].map(makeType);
		}
		return [];
	}

	function prettifySnippet(snippet:String):String {
		snippet = ~/\$\{\d:(.*?)\}/g.replace(snippet, "$1");
		return ~/\$\d/g.replace(snippet, "|");
	}
}

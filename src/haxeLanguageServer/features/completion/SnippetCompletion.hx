package haxeLanguageServer.features.completion;

import js.Promise;
import haxeLanguageServer.helper.SnippetHelper;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.protocol.Display;

using haxe.io.Path;

class SnippetCompletion {
	final context:Context;

	public function new(context) {
		this.context = context;
	}

	public function createItems<T1, T2>(data:CompletionContextData, items:Array<DisplayItem<T1>>):Promise<Array<CompletionItem>> {
		var isTypeLevel = false;
		var isPackageLevel = false;
		var fsPath = data.doc.uri.toFsPath().toString();
		for (item in items) {
			switch (item.kind) {
				case Keyword:
					var kwd:KeywordKind = item.args.name;
					switch (kwd) {
						case Class:
							isTypeLevel = true;
						case Package:
							isPackageLevel = true;
						case _:
					}
				case _:
			}
		}

		if (isTypeLevel) {
			var moduleName = fsPath.withoutDirectory().withoutExtension();
			var name = '$${1:$moduleName}';
			var abstractName = name + '($${2:Type})';
			var body = '{\n\t$0\n}';
			return new Promise((resolve, reject) -> {
				var items = [
					{label: "class", code: 'class $name $body'},
					{label: "interface", code: 'interface $name $body'},
					{label: "enum", code: 'enum $name $body'},
					{label: "typedef", code: 'typedef $name = '},
					{label: "struct", code: 'typedef $name = $body'},
					{label: "abstract", code: 'abstract $abstractName $body'},
					{label: "enum abstract", code: 'enum abstract $abstractName $body'}
				].map(function(item:{label:String, code:String}) {
						return createItem(item.label + " " + moduleName, item.code, data.replaceRange);
					});

				if (isPackageLevel) {
					context.determinePackage.onDeterminePackage({fsPath: fsPath}, null, result -> {
						var code = if (result.pack == "") "package;" else 'package ${result.pack};';
						items.push(createItem(code, code, data.replaceRange));
						resolve(items);
					}, error -> resolve(items));
				} else {
					resolve(items);
				}
			});
		}
		return Promise.resolve([]);
	}

	function createItem(label:String, code:String, replaceRange:Range):CompletionItem {
		return {
			label: label,
			kind: Snippet,
			textEdit: {
				range: replaceRange,
				newText: code
			},
			insertTextFormat: Snippet,
			documentation: {
				kind: MarkDown,
				value: DocHelper.printCodeBlock(SnippetHelper.prettify(code), Haxe)
			}
		}
	}
}

package haxeLanguageServer.features.completion;

import js.Promise;
import haxeLanguageServer.helper.SnippetHelper;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.protocol.Display;
import haxeLanguageServer.features.completion.CompletionFeature.CompletionItemOrigin;

using haxe.io.Path;

class SnippetCompletion {
	final context:Context;

	public function new(context) {
		this.context = context;
	}

	public function createItems<T1, T2>(data:CompletionContextData,
			displayItems:Array<DisplayItem<T1>>):Promise<{items:Array<CompletionItem>, displayItems:Array<DisplayItem<T1>>}> {
		var isTypeLevel = false;
		var isPackageLevel = false;
		var fsPath = data.doc.uri.toFsPath().toString();

		for (i in 0...displayItems.length) {
			var item = displayItems[i];
			switch (item.kind) {
				case Keyword:
					var kwd:KeywordKind = item.args.name;
					switch (kwd) {
						case Class, Interface, Enum, Abstract, Typedef:
							isTypeLevel = true;
							displayItems[i] = null;
						case Package:
							isPackageLevel = true;
							displayItems[i] = null;
						case _:
					}
				case _:
			};
		}

		var items = [];
		function result() {
			return {items: items, displayItems: displayItems};
		}

		if (isTypeLevel) {
			var moduleName = fsPath.withoutDirectory().withoutExtension();
			var name = '$${1:$moduleName}';
			var abstractName = name + '($${2:Type})';
			var body = '{\n\t$0\n}';
			return new Promise((resolve, reject) -> {
				items = [
					{label: "class", code: 'class $name $body'},
					{label: "interface", code: 'interface $name $body'},
					{label: "enum", code: 'enum $name $body'},
					{label: "typedef", code: 'typedef $name = '},
					{label: "struct", code: 'typedef $name = $body'},
					{label: "abstract", code: 'abstract $abstractName $body'},
					{label: "enum abstract", code: 'enum abstract $abstractName $body'}
				].map(function(item:{label:String, code:String}) {
						return createItem(item.label, item.label + " " + moduleName, item.code, data.replaceRange);
					});

				if (isPackageLevel) {
					context.determinePackage.onDeterminePackage({fsPath: fsPath}, null, pack -> {
						var code = if (pack.pack == "") "package;" else 'package ${pack.pack};';
						items.push(createItem("package", code, code, data.replaceRange));
						resolve(result());
					}, _ -> resolve(result()));
				} else {
					resolve(result());
				}
			});
		}

		return Promise.resolve(result());
	}

	function createItem(label:String, detail:String, code:String, replaceRange:Range):CompletionItem {
		return {
			label: label,
			detail: detail,
			kind: Snippet,
			sortText: "~", // sort to the end
			textEdit: {
				range: replaceRange,
				newText: code
			},
			insertTextFormat: Snippet,
			documentation: {
				kind: MarkDown,
				value: DocHelper.printCodeBlock(SnippetHelper.prettify(code), Haxe)
			},
			data: {
				origin: CompletionItemOrigin.Custom
			}
		}
	}
}

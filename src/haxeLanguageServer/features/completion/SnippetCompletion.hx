package haxeLanguageServer.features.completion;

import js.lib.Promise;
import tokentree.TokenTree;
import haxeLanguageServer.helper.SnippetHelper;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.protocol.Display;
import haxeLanguageServer.features.completion.CompletionFeature.CompletionItemOrigin;
import haxeLanguageServer.tokentree.PositionAnalyzer;

using haxe.io.Path;

typedef SnippetCompletionContextData = {
	var doc:TextDocument;
	var completionPosition:Position;
	var token:TokenTree;
	var replaceRange:Range;
}

class SnippetCompletion {
	static inline var block = '{\n\t$0\n}';

	final context:Context;

	public function new(context) {
		this.context = context;
	}

	public function createItems<T1, T2>(data:SnippetCompletionContextData,
			displayItems:Array<DisplayItem<T1>>):Promise<{items:Array<CompletionItem>, displayItems:Array<DisplayItem<T1>>}> {
		var fsPath = data.doc.uri.toFsPath().toString();

		var pos = data.completionPosition;
		var isRestOfLineEmpty = data.doc.lineAt(pos.line).substr(pos.character).trim().length == 0;

		for (i in 0...displayItems.length) {
			var item = displayItems[i];
			switch (item.kind) {
				case Keyword:
					var kwd:KeywordKind = item.args.name;
					switch (kwd) {
						case Class, Interface, Enum, Abstract, Typedef if (isRestOfLineEmpty):
							displayItems[i] = null;
						case Package:
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

		var tokenContext = PositionAnalyzer.getContext(data.token, data.doc, data.completionPosition);
		switch (tokenContext) {
			case Root(pos):
				var moduleName = fsPath.withoutDirectory().withoutExtension();
				var name = '$${1:$moduleName}';
				var abstractName = name + '($${2:T})';
				var body = '{\n\t$0\n}';
				return new Promise((resolve, reject) -> {
					if (isRestOfLineEmpty) {
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
					}

					if (pos == BeforePackage) {
						context.determinePackage.onDeterminePackage({fsPath: fsPath}, null, pack -> {
							var code = if (pack.pack == "") "package;" else 'package ${pack.pack};';
							items.push(createItem("package", code, code, data.replaceRange));
							resolve(result());
						}, _ -> resolve(result()));
					} else {
						resolve(result());
					}
				});

			case Type(type):
				var isClass = type.kind == Class || type.kind == MacroClass;
				var isAbstract = type.kind == Abstract || type.kind == EnumAbstract;
				var canInsertClassFields = type.field == null && (isClass || isAbstract);
				if (canInsertClassFields) {
					var constructor = "public function new";
					items.push(createItem("new", '$constructor()', '$constructor($1) $block', data.replaceRange));

					if (isClass) {
						var main = "static function main()";
						items.push(createItem("main", main, '$main $block', data.replaceRange));
					}
				}
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

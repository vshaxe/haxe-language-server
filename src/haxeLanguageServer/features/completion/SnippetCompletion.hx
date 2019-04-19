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
		inline function block(i:Int) {
			return '{\n\t$$$i\n}';
		}
		var body = block(0);

		var tokenContext = PositionAnalyzer.getContext(data.token, data.doc, data.completionPosition);
		switch (tokenContext) {
			case Root(pos):
				var moduleName = fsPath.withoutDirectory().withoutExtension();
				var name = '$${1:$moduleName}';
				var abstractName = name + '($${2:T})';
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
					function add(label:String, detail:String, code:String, ?sortText:String) {
						items.push(createItem(label, detail, code, data.replaceRange, sortText));
					}

					add("function", "function name()", 'function $${1:name}($$2) $body');

					if (type.kind == EnumAbstract) {
						add("var", "var name;", 'var $${1:Name}$$2;', "~");
					} else {
						add("var", "var name:T;", 'var $${1:name}:$${2:T};');
						add("final", "final name:T;", 'final $${1:name}:$${2:T};');
						add("readonly", "public var name(default, null):T;", 'public var $${1:name}(default, null):$${2:T};');
					}

					add("property", "public var name(get, set):T;", 'public var $${1:name}(get, set):$${2:T};

function get_$${1:name}():$${2:T} ${block(3)}

function set_$${1:name}($${1:name}:$${2:T}):$${2:T} $body
');

					var constructor = "public function new";
					add("new", '$constructor()', '$constructor($1) $body');

					if (isClass) {
						var main = "static function main()";
						add("main", main, '$main $body');
					}
				}
		}

		return Promise.resolve(result());
	}

	function createItem(label:String, detail:String, code:String, replaceRange:Range, ?sortText:String):CompletionItem {
		return {
			label: label,
			detail: detail,
			kind: Snippet,
			sortText: if (sortText == null) "~~" /*sort to the end*/ else sortText,
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

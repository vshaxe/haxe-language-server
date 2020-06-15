package haxeLanguageServer.features.haxe.completion;

import haxe.display.Display;
import haxeLanguageServer.features.haxe.completion.CompletionFeature.CompletionItemOrigin;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.helper.SemVer;
import haxeLanguageServer.helper.SnippetHelper;
import haxeLanguageServer.tokentree.TokenContext;
import js.lib.Promise;
import languageServerProtocol.protocol.Protocol.CompletionParams;

using haxe.io.Path;

typedef SnippetCompletionContextData = {
	var doc:TextDocument;
	var params:CompletionParams;
	var replaceRange:Range;
	var tokenContext:TokenContext;
}

class SnippetCompletion {
	final context:Context;

	public function new(context) {
		this.context = context;
	}

	public function createItems<T1, T2>(data:SnippetCompletionContextData,
			displayItems:Array<DisplayItem<T1>>):Promise<{items:Array<CompletionItem>, displayItems:Array<DisplayItem<T1>>}> {
		var fsPath = data.doc.uri.toFsPath().toString();

		var pos = data.params.position;
		var isRestOfLineEmpty = data.doc.lineAt(pos.line).substr(pos.character).trim().length == 0;

		for (i in 0...displayItems.length) {
			var item = displayItems[i];
			switch item.kind {
				case Keyword:
					var kwd:KeywordKind = item.args.name;
					switch kwd {
						case Class, Interface, Enum, Abstract, Typedef if (isRestOfLineEmpty):
							displayItems[i] = null;
						case Package, Var, Final, Function:
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

		function add(label:String, detail:String, code:String, ?sortText:String) {
			items.push(createItem(label, detail, code, data.replaceRange, sortText));
		}

		final addVar = add.bind("var", "var name:T;", 'var $${1:name}:$${2:T};');
		final addFinal = add.bind("final", "final name:T;", 'final $${1:name}:$${2:T};');
		final addFunction = add.bind("function", "function name()", 'function $${1:name}($$2) $body');

		function addReadonly(isDefaultPrivate:Bool) {
			var prefix = if (isDefaultPrivate) "public " else "";
			add("readonly", prefix + "var name(default, null):T;", prefix + 'var $${1:name}(default, null):$${2:T};');
		}
		function addProperty(isDefaultPrivate:Bool) {
			var propertyPrefix = if (isDefaultPrivate) "public " else "";
			var accessorPrefix = if (isDefaultPrivate) "" else "private ";
			add("property", propertyPrefix
				+ "var name(get, set):T;", propertyPrefix
				+ 'var $${1:name}(get, set):$${2:T};

${accessorPrefix}function get_$${1:name}():$${2:T} ${block(3)}

${accessorPrefix}function set_$${1:name}($${1:name}:$${2:T}):$${2:T} $body');

		}
		function addMain(explicitStatic:Bool) {
			var main = (if (explicitStatic) "static " else "") + "function main()";
			add("main", main, '$main $body');
		}

		function addExprLevel() {
			add("final", "final name", "final ${1:name}");
			add("var", "var name", "var ${1:name}");
			addFunction();
		}

		final supportsModuleLevelStatics = context.haxeServer.haxeVersion >= new SemVer(4, 2, 0);

		switch data.tokenContext {
			case Root(pos):
				var moduleName = fsPath.withoutDirectory().untilFirstDot();
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

					if (supportsModuleLevelStatics) {
						addVar();
						addFinal();
						addReadonly(false);
						addProperty(false);
						addFunction();
						addMain(false);
					}

					if (pos == BeforePackage) {
						context.determinePackage.onDeterminePackage({fsPath: fsPath}, null, pack -> {
							var code = if (pack.pack == "") "package;" else 'package ${pack.pack};';
							add("package", code, code);
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
					if (type.kind == EnumAbstract) {
						add("var", "var Name;", 'var $${1:Name}$$2;', "~");
						add("final", "final Name;", 'final $${1:Name}$$2;', "~");
					} else {
						addVar();
						addFinal();
						addReadonly(true);
					}

					addFunction();
					addProperty(true);

					var constructor = "public function new";
					add("new", '$constructor()', '$constructor($1) $body');

					if (isClass) {
						addMain(true);
					}
				}

				if (type.field != null) {
					addExprLevel();
				}

			case ModuleLevelStatic(_):
				addExprLevel();
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

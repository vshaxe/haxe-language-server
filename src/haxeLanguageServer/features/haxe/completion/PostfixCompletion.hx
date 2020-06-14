package haxeLanguageServer.features.haxe.completion;

import haxe.display.Display;
import haxe.display.JsonModuleTypes;
import haxeLanguageServer.features.haxe.completion.CompletionFeature;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.helper.SnippetHelper;
import haxeLanguageServer.helper.VscodeCommands;
import haxeLanguageServer.protocol.DisplayPrinter;
import languageServerProtocol.Types.CompletionItem;

using Lambda;

class PostfixCompletion {
	static inline var block = '{\n\t$0\n}';

	final context:Context;

	public function new(context) {
		this.context = context;
	}

	public function createItems<T1, T2>(data:CompletionContextData, items:Array<DisplayItem<T1>>):Array<CompletionItem> {
		var level = context.config.user.postfixCompletion.level;
		if (level == Off) {
			return [];
		}
		var context = data.params.context;
		if (context!.triggerKind == TriggerCharacter && context!.triggerCharacter != ".") {
			return [];
		}

		var subject:FieldCompletionSubject<T2>;
		switch data.mode.kind {
			case Field:
				subject = data.mode.args;
			case _:
				return [];
		}

		var type = subject.item.type;
		if (type == null) {
			return [];
		}
		var type = type.removeNulls().type;

		var expr = data.doc.getText(subject.range);
		if (expr.startsWith("(") && expr.endsWith(")")) {
			expr = expr.substring(1, expr.length - 1);
		}

		var replaceRange = data.replaceRange;
		if (replaceRange == null) {
			replaceRange = data.params.position.toRange();
		}
		var removeRange:Range = {start: subject.range.start, end: replaceRange.start};

		var result:Array<CompletionItem> = [];
		function add(item:PostfixCompletionItem) {
			result.push(createPostfixCompletionItem(item, data.doc, removeRange, replaceRange));
		}

		if (subject.iterator != null) {
			final item = subject.iterator.type.guessName();
			add({
				label: "for",
				detail: "for (item in expr)",
				insertText: 'for ($${1:$item} in $expr) $block',
				insertTextFormat: Snippet
			});
		}
		if (subject.keyValueIterator != null) {
			var key = "key";
			if (subject.keyValueIterator.key.getDotPath() == "StdTypes.Int") {
				key = "index";
			}
			add({
				label: "for k=>v",
				detail: 'for ($key => value in expr)',
				insertText: 'for ($key => value in $expr) $block',
				insertTextFormat: Snippet
			});
		}

		var dotPath = type.getDotPath();
		switch dotPath {
			case "StdTypes.Bool":
				add({
					label: "not",
					detail: "!expr",
					insertText: '!$expr',
					insertTextFormat: PlainText
				});
				add({
					label: "if",
					detail: "if (expr)",
					insertText: 'if ($expr) $block',
					insertTextFormat: Snippet
				});
				add({
					label: "else",
					detail: "if (!expr)",
					insertText: 'if (!$expr) $block',
					insertTextFormat: Snippet
				});
			case "StdTypes.Int":
				for (item in createIndexedLoops(expr)) {
					add(item);
				}
			case "StdTypes.Float":
				add({
					label: "int",
					detail: "Std.int(expr)",
					insertText: 'Std.int($expr)',
					insertTextFormat: PlainText
				});
		}

		if (level != Filtered) {
			createNonFilteredItems(dotPath, expr, add);
		}

		for (item in createLengthIterators(subject, items, expr)) {
			add(item);
		}
		var switchItem = createSwitchItem(subject, expr);
		if (switchItem != null) {
			add(switchItem);
		}

		return result;
	}

	function createNonFilteredItems(dotPath:String, expr:String, add:PostfixCompletionItem->Void) {
		if (dotPath != "String") {
			add({
				label: "string",
				detail: "Std.string(expr)",
				insertText: 'Std.string($expr)',
				insertTextFormat: PlainText
			});
		}

		add({
			label: "trace",
			detail: "trace(expr);",
			insertText: 'trace($${1:$expr});',
			insertTextFormat: Snippet
		});
		// TODO: check if we're on a sys target
		add({
			label: "print",
			detail: "Sys.println(expr);",
			insertText: 'Sys.println($${1:$expr});',
			insertTextFormat: Snippet
		});

		add({
			label: "is",
			detail: "Std.is(expr, T)",
			insertText: 'Std.is($expr, $1)',
			insertTextFormat: Snippet,
			command: TriggerSuggest
		});
		add({
			label: "unsafe cast",
			detail: "cast expr",
			insertText: 'cast $expr',
			insertTextFormat: PlainText
		});
		add({
			label: "safe cast",
			detail: "cast(expr, T)",
			insertText: 'cast($expr, $1)',
			insertTextFormat: Snippet,
			command: TriggerSuggest
		});
		add({
			label: "type check",
			detail: "(expr : T)",
			insertText: '($expr : $1)',
			insertTextFormat: Snippet,
			command: TriggerSuggest
		});

		// TODO: check if subject is nullable on current target?
		add({
			label: "null",
			detail: "if (expr == null)",
			insertText: 'if ($expr == null) $block',
			insertTextFormat: Snippet
		});
		add({
			label: "not null",
			detail: "if (expr != null)",
			insertText: 'if ($expr != null) $block',
			insertTextFormat: Snippet
		});

		add({
			label: "return",
			detail: "return expr;",
			insertText: 'return $expr;',
			insertTextFormat: PlainText
		});

		function createLocalItem(kind:String, sortText:String):PostfixCompletionItem {
			return {
				label: kind,
				detail: '$kind name = $expr;',
				insertText: '$kind $${1:name} = $expr;',
				insertTextFormat: Snippet,
				eat: ";"
			};
		}

		add(createLocalItem("var", "1"));
		add(createLocalItem("final", "2"));
	}

	/**
		Adds `for i in 0...foo.<field>` style iterators for:
			- variables returning `Int`
			- argument-less functions returning `Int`
		as long as the field name indicates it's a length/count/size.
	**/
	function createLengthIterators<T1, T2>(subject:FieldCompletionSubject<T1>, items:Array<DisplayItem<T2>>, expr:String):Array<PostfixCompletionItem> {
		var result:Array<PostfixCompletionItem> = [];

		for (item in items) {
			switch (item.kind) {
				case ClassField:
					var field = item.args.field.name;
					if (!~/^(get)?(length|count|size)$/i.match(field)) {
						continue;
					}
					var type = item.type.removeNulls().type;
					type = switch type.kind {
						case TFun:
							field += "()";
							var args:JsonFunctionSignature = type.args;
							if (args.args.length > 0) {
								continue;
							}
							args.ret;
						case _:
							type;
					}
					switch type.getDotPath() {
						case "StdTypes.Int" | "UInt":
							result = result.concat(createIndexedLoops('$expr.$field'));
					}
				case _:
			}
		}
		return result;
	}

	function createIndexedLoops(field:String):Array<PostfixCompletionItem> {
		var whileForward = 'var i = 0;
while (i < $field) {
	$0
	i++;
}';
		var whileBackward = 'var i = $field;
while (i-- > 0) {
	$0
}';
		return [
			{
				label: 'for 0...$field',
				insertText: 'for (i in 0...$field) $block',
				insertTextFormat: Snippet,
				showCode: true
			},
			{
				label: 'while 0...$field',
				insertText: whileForward,
				insertTextFormat: Snippet,
				showCode: true
			},
			{
				label: 'while $field...0',
				insertText: whileBackward,
				insertTextFormat: Snippet,
				showCode: true
			}
		];
	}

	function createSwitchItem<T>(subject:FieldCompletionSubject<T>, expr:String):Null<PostfixCompletionItem> {
		var moduleType = subject.moduleTypeFollowed;
		if (moduleType == null) {
			moduleType = subject.moduleType;
		}
		if (moduleType == null) {
			return null;
		}
		var printer = new DisplayPrinter();
		var parentheses = context.config.user.codeGeneration.switch_.parentheses;

		function make(insertText:String):PostfixCompletionItem {
			return {
				label: "switch",
				detail: printer.printSwitchSubject("expr", parentheses) + " {cases...}",
				insertText: insertText,
				insertTextFormat: Snippet,
				showCode: true
			};
		}

		var nullable = subject.item.type.removeNulls().nullable;
		switch moduleType.kind {
			case Enum:
				var e:JsonEnum = moduleType.args;
				if (e.constructors.length > 0) {
					return make(printer.printSwitchOnEnum(expr, e, nullable, true, parentheses));
				}
			case Abstract if (moduleType.meta.hasMeta(Enum)):
				var a:JsonAbstract = moduleType.args;
				if (a.impl != null && a.impl.statics.exists(f -> f.isEnumAbstractField())) {
					return make(printer.printSwitchOnEnumAbstract(expr, a, nullable, true, parentheses));
				}
			case Abstract if (moduleType.moduleName == "StdTypes" && moduleType.name == "Bool"):
				return make(printer.printSwitch(expr, ["true", "false"], nullable, true, parentheses));
			case _:
				var item = make(printer.printSwitchSubject(expr, parentheses) + ' {\n\tcase $0\n}');
				item.command = TriggerSuggest;
				return item;
		}
		return null;
	}

	function createPostfixCompletionItem(data:PostfixCompletionItem, doc:TextDocument, removeRange:Range, replaceRange:Range):CompletionItem {
		if (data.eat != null) {
			var pos = replaceRange.end;
			var nextChar = doc.getText({start: pos, end: pos.translate(0, 1)});
			if (data.eat == nextChar) {
				replaceRange = {start: replaceRange.start, end: pos.translate(0, 1)};
			}
		};
		var item:CompletionItem = {
			label: data.label,
			sortText: "~", // sort to the end
			kind: Snippet,
			insertTextFormat: data.insertTextFormat,
			textEdit: {
				newText: data.insertText,
				range: replaceRange
			},
			additionalTextEdits: [
				{
					range: removeRange,
					newText: ""
				}
			],
			data: {
				origin: CompletionItemOrigin.Custom
			}
		}
		if (data.showCode) {
			item.documentation = {
				kind: MarkDown,
				value: DocHelper.printCodeBlock(SnippetHelper.prettify(data.insertText), Haxe)
			}
		}
		if (data.detail != null) {
			item.detail = data.detail;
		}
		if (data.command != null) {
			item.command = data.command;
		}
		return item;
	}
}

private typedef PostfixCompletionItem = {
	var label:String;
	var ?detail:String;
	var insertText:String;
	var insertTextFormat:InsertTextFormat;
	var ?eat:String;
	var ?showCode:Bool;
	var ?command:Command;
}

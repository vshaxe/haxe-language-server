package haxeLanguageServer.features.haxe.completion;

import haxe.display.Display;
import haxe.display.JsonModuleTypes;
import haxeLanguageServer.features.haxe.completion.CompletionFeature;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.helper.SnippetHelper;
import haxeLanguageServer.helper.VscodeCommands;
import haxeLanguageServer.protocol.DisplayPrinter;
import haxeLanguageServer.protocol.DotPath;
import languageServerProtocol.Types.Command;
import languageServerProtocol.Types.CompletionItem;
import languageServerProtocol.Types.InsertTextFormat;

using Lambda;

class PostfixCompletion {
	static inline final block = '{\n\t$0\n}';

	final context:Context;

	public function new(context) {
		this.context = context;
	}

	public function createItems<T1, T2>(data:CompletionContextData, items:Array<DisplayItem<T1>>):Array<CompletionItem> {
		final level = context.config.user.postfixCompletion.level;
		if (level == Off) {
			return [];
		}
		final context = data.params.context;
		if (context?.triggerKind == TriggerCharacter && context?.triggerCharacter != ".") {
			return [];
		}

		var subject:FieldCompletionSubject<T2>;
		final mode = data.mode;
		if (mode == null) {
			return [];
		}
		switch mode.kind {
			case Field if (mode.args != null):
				subject = mode.args;
			case _:
				return [];
		}

		final type = subject.item.type;
		if (type == null || subject.range == null) {
			return [];
		}
		final type = type.removeNulls().type;

		var expr = data.doc.getText(subject.range);
		if (expr.startsWith("(") && expr.endsWith(")")) {
			expr = expr.substring(1, expr.length - 1);
		}

		var replaceRange = data.replaceRange;
		if (replaceRange == null) {
			replaceRange = data.params.position.toRange();
		}
		final removeRange:Range = {start: subject.range.start, end: replaceRange.start};

		final result:Array<CompletionItem> = [];
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
			final key = if (subject.keyValueIterator.key.getDotPath() == Std_Int) "index" else "key";
			add({
				label: "for k=>v",
				detail: 'for ($key => value in expr)',
				insertText: 'for ($key => value in $expr) $block',
				insertTextFormat: Snippet
			});
		}

		final dotPath = type.getDotPath();
		switch dotPath {
			case Std_Bool:
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

			case Std_Int:
				for (item in createIndexedLoops(expr)) {
					add(item);
				}

			case Std_Float:
				add({
					label: "int",
					detail: "Std.int(expr)",
					insertText: 'Std.int($expr)',
					insertTextFormat: PlainText
				});

			case _:
		}

		if (level != Filtered) {
			createNonFilteredItems(dotPath, expr, add);
		}

		for (item in createLengthIterators(subject, items, expr)) {
			add(item);
		}
		final switchItem = createSwitchItem(subject, expr);
		if (switchItem != null) {
			add(switchItem);
		}

		return result;
	}

	function createNonFilteredItems(dotPath:Null<DotPath>, expr:String, add:PostfixCompletionItem->Void) {
		if (dotPath != Std_String) {
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
			insertTextFormat: Snippet,
			eat: ";"
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
			switch item.kind {
				case ClassField:
					var field = item.args.field.name;
					if (!~/^(get)?(length|count|size)$/i.match(field) || item.type == null) {
						continue;
					}
					var type = item.type.removeNulls().type;
					type = switch type.kind {
						case TFun:
							field += "()";
							final args:JsonFunctionSignature = type.args;
							if (args.args.length > 0) {
								continue;
							}
							args.ret;
						case _:
							type;
					}
					switch type.getDotPath() {
						case Std_Int | Std_UInt:
							result = result.concat(createIndexedLoops('$expr.$field'));
						case _:
					}
				case _:
			}
		}
		return result;
	}

	function createIndexedLoops(field:String):Array<PostfixCompletionItem> {
		final whileForward = 'var i = 0;
while (i < $field) {
	$0
	i++;
}';
		final whileBackward = 'var i = $field;
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
		final type = subject.item.type;
		if (type == null) {
			return null;
		}

		final printer = new DisplayPrinter();
		final parentheses = context.config.user.codeGeneration.switch_.parentheses;

		function make(insertText:String):PostfixCompletionItem {
			return {
				label: "switch",
				detail: printer.printSwitchSubject("expr", parentheses) + " {cases...}",
				insertText: insertText,
				insertTextFormat: Snippet,
				showCode: true
			};
		}

		final nullable = type.removeNulls().nullable;
		switch moduleType.kind {
			case Enum:
				final e:JsonEnum = moduleType.args;
				if (e.constructors.length > 0) {
					return make(printer.printSwitchOnEnum(expr, e, nullable, true, parentheses));
				}
			case Abstract if (moduleType.meta.hasMeta(Enum)):
				final a:JsonAbstract = moduleType.args;
				if (a.impl != null && a.impl.statics.exists(f -> f.isEnumAbstractField())) {
					return make(printer.printSwitchOnEnumAbstract(expr, a, nullable, true, parentheses));
				}
			case Abstract if (moduleType.moduleName == "StdTypes" && moduleType.name == "Bool"):
				return make(printer.printSwitch(expr, ["true", "false"], nullable, true, parentheses));
			case _:
				final item = make(printer.printSwitchSubject(expr, parentheses) + ' {\n\tcase $0\n}');
				item.command = TriggerSuggest;
				return item;
		}
		return null;
	}

	function createPostfixCompletionItem(data:PostfixCompletionItem, doc:HxTextDocument, removeRange:Range, replaceRange:Range):CompletionItem {
		if (data.eat != null) {
			final pos = replaceRange.end;
			var nextChar = doc.characterAt(pos);
			// if user writes `.l abel` too fast, detect it and check next char again
			if (nextChar == data.label.charAt(0) && nextChar != data.eat) {
				nextChar = doc.characterAt(pos.translate(0, 1));
			}
			if (nextChar == data.eat) {
				replaceRange = {start: replaceRange.start, end: pos.translate(0, 1)};
			}
		};
		final item:CompletionItem = {
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
		if (data.showCode == true) {
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
	final label:String;
	final ?detail:String;
	final insertText:String;
	final insertTextFormat:InsertTextFormat;
	final ?eat:String;
	final ?showCode:Bool;
	var ?command:Command;
}

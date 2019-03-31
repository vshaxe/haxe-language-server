package haxeLanguageServer.features.completion;

import haxe.display.JsonModuleTypes;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.protocol.Display;
import haxeLanguageServer.protocol.helper.DisplayPrinter;
import haxeLanguageServer.features.completion.CompletionFeature;
import languageServerProtocol.Types.CompletionItem;

using Lambda;

class PostfixCompletion {
	static inline var forBody = '{\n\t$0\n}';

	public function new() {}

	public function createItems<T1, T2>(data:CompletionContextData, items:Array<DisplayItem<T1>>):Array<CompletionItem> {
		var subject:FieldCompletionSubject<T2>;
		switch (data.mode.kind) {
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

		var range = subject.range;
		var replaceRange:Range = {
			start: range.start,
			end: data.completionPosition
		};
		var expr = data.doc.getText(range);
		if (expr.startsWith("(") && expr.endsWith(")")) {
			expr = expr.substring(1, expr.length - 1);
		}

		var result:Array<CompletionItem> = [];
		function add(item:PostfixCompletionItem) {
			result.push(createPostfixCompletionItem(item, data.doc, replaceRange));
		}

		function iterator(item:String = "item") {
			add({
				label: "for",
				detail: "for (item in expr)",
				insertText: 'for ($${1:$item} in $expr) $forBody',
				insertTextFormat: Snippet
			});
		}
		function keyValueIterator(key:String = "key") {
			add({
				label: "for k=>v",
				detail: 'for ($key => value in expr)',
				insertText: 'for ($key => value in $expr) $forBody',
				insertTextFormat: Snippet
			});
		}

		var dotPath = type.getDotPath();

		var hasIteratorApi = subject.iterator != null || subject.keyValueIterator != null;
		if (hasIteratorApi) {
			if (subject.iterator != null) {
				iterator(subject.iterator.type.guessName());
			}
			if (subject.keyValueIterator != null) {
				keyValueIterator();
			}
		} else {
			switch (type.kind) {
				case TAbstract | TInst:
					var path = type.args;
					// TODO: remove hardcoded iterator() / keyValueIterator() handling sometime after Haxe 4 releases
					if (!hasIteratorApi) {
						switch (dotPath) {
							case "Array":
								iterator(path.params[0].guessName());
							case "haxe.ds.Map":
								keyValueIterator();
								iterator(path.params[1].guessName());
							case "haxe.ds.List":
								keyValueIterator("index");
								iterator(path.params[0].guessName());
						}
					}
				case _:
			}
		}

		switch (dotPath) {
			case "StdTypes.Bool":
				add({
					label: "if",
					detail: "if (expr)",
					insertText: 'if ($expr) ',
					insertTextFormat: PlainText
				});
			case "StdTypes.Int":
				add({
					label: "fori",
					detail: "for (i in 0...expr)",
					insertText: 'for (i in 0...$expr) $forBody',
					insertTextFormat: Snippet
				});
			case "StdTypes.Float":
				add({
					label: "int",
					detail: "Std.int(expr)",
					insertText: 'Std.int($expr)',
					insertTextFormat: PlainText
				});
		}

		for (item in createIndexedIterators(subject, items, expr)) {
			add(item);
		}
		var switchItem = createSwitchItem(subject, expr);
		if (switchItem != null) {
			add(switchItem);
		}

		return result;
	}

	/**
		Adds `for i in 0...foo.<field>` style iterators for:
			- variables returning `Int`
			- argument-less functions returning `Int`
		as long as the field name indicates it's a length/count/size.
	**/
	function createIndexedIterators<T1, T2>(subject:FieldCompletionSubject<T1>, items:Array<DisplayItem<T2>>, expr:String):Array<PostfixCompletionItem> {
		var result:Array<PostfixCompletionItem> = [];
		function make(field:String) {
			result.push({
				label: 'for i...$field',
				detail: 'for (i in 0...expr.$field)',
				insertText: 'for (i in 0...$expr.$field) $forBody',
				insertTextFormat: Snippet
			});
		}
		for (item in items) {
			switch (item.kind) {
				case ClassField:
					var field = item.args.field.name;
					if (!~/^(get)?(length|count|size)$/i.match(field)) {
						continue;
					}
					var type = item.type.removeNulls().type;
					type = switch (type.kind) {
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
					switch (type.getDotPath()) {
						case "StdTypes.Int" | "UInt":
							make(field);
					}
				case _:
			}
		}
		return result;
	}

	function createSwitchItem<T>(subject:FieldCompletionSubject<T>, expr:String):Null<PostfixCompletionItem> {
		var moduleType = subject.moduleTypeFollowed;
		if (moduleType == null) {
			moduleType = subject.moduleType;
		}
		if (moduleType == null) {
			return null;
		}

		// switching on a concrete enum value _works_, but it's sort of pointless
		switch (subject.item.kind) {
			case EnumField:
				return null;
			case EnumAbstractField:
				return null;
			case _:
		}

		function make(print:(snippets:Bool) -> String):PostfixCompletionItem {
			return {
				label: "switch",
				detail: "switch (expr) {cases...}",
				insertText: print(true),
				insertTextFormat: Snippet,
				code: print(false)
			};
		}

		var nullable = subject.item.type.removeNulls().nullable;
		var printer = new DisplayPrinter();
		switch (moduleType.kind) {
			case Enum:
				var e:JsonEnum = moduleType.args;
				if (e.constructors.length > 0) {
					return make(printer.printSwitchOnEnum.bind(expr, e, nullable));
				}
			case Abstract if (moduleType.meta.hasMeta(Enum)):
				var a:JsonAbstract = moduleType.args;
				if (a.impl != null && a.impl.statics.exists(Helper.isEnumAbstractField)) {
					return make(printer.printSwitchOnEnumAbstract.bind(expr, a, nullable));
				}
			case _:
		}
		return null;
	}

	function createPostfixCompletionItem(data:PostfixCompletionItem, doc:TextDocument, replaceRange:Range):CompletionItem {
		var item:CompletionItem = {
			label: data.label,
			detail: data.detail,
			sortText: data.sortText,
			filterText: doc.getText(replaceRange) + " " + data.label, // https://github.com/Microsoft/vscode/issues/38982
			kind: Snippet,
			insertTextFormat: data.insertTextFormat,
			textEdit: {
				newText: data.insertText,
				range: replaceRange.end.toRange()
			},
			additionalTextEdits: [{
				range: replaceRange,
				newText: ""
			}],
			data: {
				origin: CompletionItemOrigin.Custom
			}
		}

		if (data.code != null) {
			item.documentation = {
				kind: MarkDown,
				value: DocHelper.printCodeBlock(data.code, Haxe)
			}
		}

		return item;
	}
}

private typedef PostfixCompletionItem = {
	var label:String;
	var detail:String;
	var insertText:String;
	var insertTextFormat:InsertTextFormat;
	var ?code:String;
	var ?sortText:String;
}

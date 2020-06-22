package haxeLanguageServer.features.haxe.completion;

import haxe.display.Display.ToplevelCompletion;
import haxe.display.JsonModuleTypes.JsonType;
import haxe.display.JsonModuleTypes.JsonTypePathWithParams;
import haxeLanguageServer.features.haxe.completion.CompletionFeature;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.helper.ImportHelper;
import haxeLanguageServer.helper.SnippetHelper;
import haxeLanguageServer.protocol.DisplayPrinter;

class ExpectedTypeCompletion {
	final context:Context;

	public function new(context) {
		this.context = context;
	}

	public function createItems<T, TType>(data:CompletionContextData):Array<CompletionItem> {
		var toplevel:Null<ToplevelCompletion<TType>>;
		switch data.mode!.kind {
			case Toplevel, Pattern:
				toplevel = data.mode!.args;
			case _:
				return [];
		}
		if (toplevel == null) {
			return [];
		}

		final expectedTypeFollowed:Null<JsonType<TType>> = toplevel.expectedTypeFollowed;
		if (expectedTypeFollowed == null) {
			return [];
		}

		var items:Array<ExpectedTypeCompletionItem> = [];
		final types = expectedTypeFollowed.resolveTypes();
		for (type in types) {
			items = items.concat(createItemsForType(type, data));
		}
		items = items.filterDuplicates((item1, item2) -> item1.insertText == item2.insertText);
		return items.map(createExpectedTypeCompletionItem.bind(_, data.params.position));
	}

	function createItemsForType<T>(concreteType:JsonType<T>, data:CompletionContextData):Array<ExpectedTypeCompletionItem> {
		final items:Array<ExpectedTypeCompletionItem> = [];

		final anonFormatting = context.config.user.codeGeneration.functions.anonymous;
		final printer = new DisplayPrinter(false, Shadowed, anonFormatting);
		switch concreteType.kind {
			case TInst | TAbstract:
				final type:JsonTypePathWithParams = concreteType.args;
				function getNested(i:Int) {
					return createItemsForType(type.params[i], data)[0];
				}
				switch concreteType.getDotPath() {
					case Array | ReadOnlyArray:
						final nested = getNested(0);
						final item:ExpectedTypeCompletionItem = {
							label: "[]",
							detail: "Generate array literal",
							insertText: "[" + (if (nested == null) "$1" else nested.insertText) + "]",
							insertTextFormat: Snippet
						};
						item.code = SnippetHelper.prettify(item.insertText);
						items.push(item);

					case Map:
						final nested = getNested(1);
						final item:ExpectedTypeCompletionItem = {
							label: "[key => value]",
							detail: "Generate map literal",
							insertText: "[${1:key} => " + (if (nested == null) {
								"${2:value}";
							} else {
								SnippetHelper.offset(nested.insertText, 1);
							}) + "]",
							insertTextFormat: Snippet
						};
						item.code = SnippetHelper.prettify(item.insertText);
						items.push(item);

					case EReg:
						items.push({
							label: "~/regex/",
							detail: "Generate regex literal",
							insertText: "~/${1:regex}/",
							insertTextFormat: Snippet
						});

					case _:
				}
			case TAnonymous:
				// TODO: support @:structInit
				final anon = concreteType.args;
				final singleLine = data.mode!.kind == Pattern;
				final allFields = printer.printObjectLiteral(anon, singleLine, false, true);
				final requiredFields = printer.printObjectLiteral(anon, singleLine, true, true);
				if (allFields == requiredFields) {
					items.push({
						label: if (anon.fields.length == 0) "{}" else "{fields...}",
						detail: "Generate object literal",
						insertText: allFields,
						insertTextFormat: Snippet,
						code: printer.printObjectLiteral(anon, singleLine, false, false)
					});
				} else {
					items.push({
						label: "{all fields...}",
						detail: "Generate object literal\n(all fields)",
						insertText: allFields,
						insertTextFormat: Snippet,
						code: printer.printObjectLiteral(anon, singleLine, false, false)
					});
					items.push({
						label: "{required fields...}",
						detail: "Generate object literal\n(only required fields)",
						insertText: requiredFields,
						insertTextFormat: Snippet,
						code: printer.printObjectLiteral(anon, singleLine, true, false)
					});
				}
			case TFun:
				final signature = concreteType.args;
				final definition = printer.printAnonymousFunctionDefinition(signature);
				items.push({
					label: definition,
					detail: "Generate anonymous function",
					insertText: definition,
					insertTextFormat: PlainText,
					additionalTextEdits: createFunctionImportsEdit(data.doc, data.importPosition, context, concreteType, anonFormatting)
				});
			case _:
		}

		return items;
	}

	function createExpectedTypeCompletionItem(data:ExpectedTypeCompletionItem, position:Position):CompletionItem {
		final item:CompletionItem = {
			label: data.label,
			detail: data.detail,
			sortText: "0",
			kind: Snippet,
			textEdit: {
				newText: data.insertText,
				range: position.toRange()
			},
			insertTextFormat: data.insertTextFormat,
			additionalTextEdits: data.additionalTextEdits,
			data: {
				origin: Custom
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

private typedef ExpectedTypeCompletionItem = {
	final label:String;
	final detail:String;
	final insertText:String;
	final insertTextFormat:InsertTextFormat;
	var ?code:String;
	final ?additionalTextEdits:Array<TextEdit>;
}

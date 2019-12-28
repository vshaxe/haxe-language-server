package haxeLanguageServer.features.completion;

import haxe.display.Display.ToplevelCompletion;
import haxe.display.JsonModuleTypes.JsonType;
import haxeLanguageServer.features.completion.CompletionFeature;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.helper.ImportHelper;
import haxeLanguageServer.protocol.DisplayPrinter;

class ExpectedTypeCompletion {
	final context:Context;

	public function new(context) {
		this.context = context;
	}

	public function createItems<T, TType>(data:CompletionContextData):Array<CompletionItem> {
		var toplevel:ToplevelCompletion<TType>;
		switch data.mode.kind {
			case Toplevel, Pattern:
				toplevel = data.mode.args;
			case _:
				return [];
		}
		if (toplevel == null) {
			return [];
		}

		var expectedTypeFollowed:JsonType<TType> = toplevel.expectedTypeFollowed;
		if (expectedTypeFollowed == null) {
			return [];
		}

		var items:Array<CompletionItem> = [];
		var types = expectedTypeFollowed.resolveTypes();
		for (type in types) {
			items = items.concat(createItemsForType(type, data));
		}
		items = items.filterDuplicates((item1, item2) -> item1.textEdit.newText == item2.textEdit.newText);
		return items;
	}

	function createItemsForType<T>(concreteType:JsonType<T>, data:CompletionContextData):Array<CompletionItem> {
		var items:Array<ExpectedTypeCompletionItem> = [];

		var anonFormatting = context.config.user.codeGeneration.functions.anonymous;
		var printer = new DisplayPrinter(false, Shadowed, anonFormatting);
		switch concreteType.kind {
			case TAnonymous:
				// TODO: support @:structInit
				var anon = concreteType.args;
				var singleLine = data.mode.kind == Pattern;
				var allFields = printer.printObjectLiteral(anon, singleLine, false, true);
				var requiredFields = printer.printObjectLiteral(anon, singleLine, true, true);
				if (allFields == requiredFields) {
					items.push({
						label: if (anon.fields.length == 0) "{}" else "{fields...}",
						detail: "Auto-generate object literal",
						insertText: allFields,
						insertTextFormat: Snippet,
						code: printer.printObjectLiteral(anon, singleLine, false, false)
					});
				} else {
					items.push({
						label: "{all fields...}",
						detail: "Auto-generate object literal\n(all fields)",
						insertText: allFields,
						insertTextFormat: Snippet,
						code: printer.printObjectLiteral(anon, singleLine, false, false)
					});
					items.push({
						label: "{required fields...}",
						detail: "Auto-generate object literal\n(only required fields)",
						insertText: requiredFields,
						insertTextFormat: Snippet,
						code: printer.printObjectLiteral(anon, singleLine, true, false)
					});
				}
			case TFun:
				var signature = concreteType.args;
				var definition = printer.printAnonymousFunctionDefinition(signature);
				items.push({
					label: definition,
					detail: "Auto-generate anonymous function",
					insertText: definition,
					insertTextFormat: PlainText,
					additionalTextEdits: ImportHelper.createFunctionImportsEdit(data.doc, data.importPosition, context, concreteType, anonFormatting)
				});
			case _:
		}

		return items.map(createExpectedTypeCompletionItem.bind(_, data.params.position));
	}

	function createExpectedTypeCompletionItem(data:ExpectedTypeCompletionItem, position:Position):CompletionItem {
		var item:CompletionItem = {
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
	var label:String;
	var detail:String;
	var insertText:String;
	var insertTextFormat:InsertTextFormat;
	var ?code:String;
	var ?additionalTextEdits:Array<TextEdit>;
}

package haxeLanguageServer.features.completion;

import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.features.completion.CompletionFeature;
import haxeLanguageServer.protocol.helper.DisplayPrinter;
import haxeLanguageServer.protocol.Display.ToplevelCompletion;
import haxeLanguageServer.protocol.Display.CompletionMode;
import haxe.display.JsonModuleTypes.JsonType;

class ExpectedTypeCompletion {
    final context:Context;

    public function new(context) {
        this.context = context;
    }

    public function createItems<T,TType>(mode:CompletionMode<T>, position:Position, doc:TextDocument, textBefore:String):Array<CompletionItem> {
        var toplevel:ToplevelCompletion<TType>;
        switch (mode.kind) {
            case Toplevel: toplevel = mode.args;
            case _: return [];
        }
        if (toplevel == null) {
            return [];
        }

        var expectedTypeFollowed:JsonType<TType> = toplevel.expectedTypeFollowed;
        if (expectedTypeFollowed == null) {
            return [];
        }

        var items:Array<CompletionItem> = [];
        function add(data:ExpectedTypeCompletionItem) {
            items.push(createExpectedTypeCompletionItem(data, position));
        }

        var printer = new DisplayPrinter(false, null, context.config.codeGeneration.functions.anonymous);

        switch (expectedTypeFollowed.kind) {
            case TAnonymous:
                // TODO: support @:structInit
                var anon = expectedTypeFollowed.args;
                var allFields = printer.printObjectLiteral(anon, false, true);
                var requiredFields = printer.printObjectLiteral(anon, true, true);
                if (allFields == requiredFields) {
                    add({
                        label: if (anon.fields.length == 0) "{}" else "{fields...}",
                        detail: "Auto-generate object literal",
                        insertText: allFields,
                        insertTextFormat: Snippet,
                        code: printer.printObjectLiteral(anon, false, false)
                    });
                } else {
                    add({
                        label: "{all fields...}",
                        detail: "Auto-generate object literal\n(all fields)",
                        insertText: allFields,
                        insertTextFormat: Snippet,
                        code: printer.printObjectLiteral(anon, false, false)
                    });
                    add({
                        label: "{required fields...}",
                        detail: "Auto-generate object literal\n(only required fields)",
                        insertText: requiredFields,
                        insertTextFormat: Snippet,
                        code: printer.printObjectLiteral(anon, true, false)
                    });
                }
            case TFun:
                var definition = printer.printAnonymousFunctionDefinition(expectedTypeFollowed.args);
                add({
                    label: definition,
                    detail: "Auto-generate anonymous function",
                    insertText: definition,
                    insertTextFormat: PlainText
                });
            case _:
        }
        return items;
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
}

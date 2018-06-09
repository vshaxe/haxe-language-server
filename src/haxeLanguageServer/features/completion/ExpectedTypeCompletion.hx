package haxeLanguageServer.features.completion;

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

        switch (expectedTypeFollowed.kind) {
            case TAnonymous:
                var fields = expectedTypeFollowed.args.fields;
                var allFields = [];
                var requiredFields = [];
                for (i in 0...fields.length) {
                    var name = fields[i].name;
                    var field = "\t" + name + ': $${${i+1}:$name}';
                    allFields.push(field);
                    if (!fields[i].meta.hasMeta(Optional)) {
                        requiredFields.push(field);
                    }
                }
                // TODO: support @:structInit
                add({
                    label: "{all fields...}",
                    detail: "Auto-generate object literal\n(all fields)",
                    insertText: '{\n${allFields.join(",\n")}\n}',
                    insertTextFormat: Snippet
                });
                add({
                    label: "{required fields...}",
                    detail: "Auto-generate object literal\n(only required fields)",
                    insertText: '{\n${requiredFields.join(",\n")}\n}',
                    insertTextFormat: Snippet
                });
            case TFun:
                var printer = new DisplayPrinter(false, null, context.config.codeGeneration.functions.anonymous);
                var definition = printer.printAnonymousFunctionDefinition(expectedTypeFollowed.args);
                add({
                    label: definition + "{}",
                    detail: "Auto-generate anonymous function",
                    insertText: definition,
                    insertTextFormat: PlainText
                });
            case _:
        }
        return items;
    }

    function createExpectedTypeCompletionItem(data:ExpectedTypeCompletionItem, position:Position):CompletionItem {
        return {
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
    }
}

private typedef ExpectedTypeCompletionItem = {
    var label:String;
    var detail:String;
    var insertText:String;
    var insertTextFormat:InsertTextFormat;
}

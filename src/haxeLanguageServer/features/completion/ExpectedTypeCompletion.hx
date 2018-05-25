package haxeLanguageServer.features.completion;

import haxeLanguageServer.protocol.Display.ToplevelCompletion;
import haxeLanguageServer.protocol.Display.CompletionMode;
import haxe.display.JsonModuleTypes.JsonType;

class ExpectedTypeCompletion {
    public function new() {}

    public function createItems<T,TType>(mode:CompletionMode<T>, position:Position, textBefore:String):Array<CompletionItem> {
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

        var whitespaceRegex = ~/^\s*/;
        whitespaceRegex.match(textBefore);
        var indent = whitespaceRegex.matched(0);

        switch (expectedTypeFollowed.kind) {
            case TAnonymous:
                var fields = expectedTypeFollowed.args.fields;
                var printedFields = [];
                for (i in 0...fields.length) {
                    var name = fields[i].name;
                    // TODO: properly detect indent
                    printedFields.push(indent + "\t" + name + ': $${${i+1}:$name}');
                    if (i < fields.length - 1) {
                        printedFields[i] += ",";
                    }
                }
                items.push({
                    label: "{fields...}",
                    sortText: "0",
                    detail: "Auto-generate object literal fields",
                    kind: Snippet,
                    insertTextFormat: Snippet,
                    textEdit: {
                        newText: '{\n${printedFields.join("\n")}$indent\n}',
                        range: position.toRange()
                    }
                });
            case _:
        }
        trace(items);
        return items;
    }
}

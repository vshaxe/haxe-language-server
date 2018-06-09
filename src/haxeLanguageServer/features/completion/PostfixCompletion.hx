package haxeLanguageServer.features.completion;

import haxeLanguageServer.helper.DocHelper;
import haxe.display.JsonModuleTypes;
import haxeLanguageServer.protocol.Display;
import languageServerProtocol.Types.CompletionItem;
import haxeLanguageServer.protocol.helper.DisplayPrinter;
import haxeLanguageServer.features.completion.CompletionFeature.CompletionItemOrigin;
import haxeLanguageServer.helper.ArgumentNameHelper.guessArgumentName;

class PostfixCompletion {
    public function new() {}

    public function createItems<TMode,TItem>(mode:CompletionMode<TMode>, position:Position, doc:TextDocument):Array<CompletionItem> {
        var subject:FieldCompletionSubject<TItem>;
        switch (mode.kind) {
            case Field: subject = mode.args;
            case _: return [];
        }

        var type = subject.item.type;
        var moduleType = subject.moduleType;
        if (type == null) {
            return [];
        }

        var range = subject.range;
        var replaceRange:Range = {
            start: range.start,
            end: position
        };
        var expr = doc.getText(range);
        if (expr.startsWith("(") && expr.endsWith(")")) {
            expr = expr.substring(1, expr.length - 1);
        }

        var items:Array<CompletionItem> = [];
        function add(data:PostfixCompletionItem) {
            items.push(createPostfixCompletionItem(data, doc, replaceRange));
        }

        switch (type.kind) {
            case TAbstract | TInst if (type.args.path.pack.length == 0):
                var path:JsonPathWithParams = type.args;
                switch (type.args.path.name) {
                    case "Int":
                        add({
                            label: "fori",
                            detail: "for (i in 0...expr)",
                            insertText: 'for (i in 0...$expr) ',
                            insertTextFormat: PlainText
                        });
                    case "Float":
                        add({
                            label: "int",
                            detail: "Std.int(expr)",
                            insertText: 'Std.int($expr)',
                            insertTextFormat: PlainText
                        });
                    case "Array":
                        var itemType:JsonType<Dynamic> = path.params[0];
                        var itemName = switch (itemType.kind) {
                            case TInst | TEnum | TType | TAbstract:
                                guessArgumentName(itemType.args.path.name);
                            case TMono, _:
                                "item";
                        }
                        add({
                            label: "for",
                            detail: "for (item in expr)",
                            insertText: 'for ($${1:$itemName} in $expr) ',
                            insertTextFormat: Snippet
                        });
                        add({
                            label: "fori",
                            detail: "for (i in 0...expr.length)",
                            insertText: 'for (i in 0...$expr.length) ',
                            insertTextFormat: PlainText
                        });
                    case "Bool":
                        add({
                            label: "if",
                            detail: "if (expr)",
                            insertText: 'if ($expr) ',
                            insertTextFormat: PlainText
                        });
                }
            case _:
        }

        function addSwitchItem(print:(snippets:Bool)->String) {
            add({
                label: "switch",
                detail: "switch (expr) {cases...}",
                insertText: print(true),
                insertTextFormat: Snippet,
                code: print(false)
            });
        }

        var printer = new DisplayPrinter();
        if (moduleType != null) {
            switch (moduleType.kind) {
                case Enum:
                    addSwitchItem(printer.printSwitchOnEnum.bind(expr, moduleType.args));
                case Abstract if (moduleType.meta.hasMeta(Enum)):
                    addSwitchItem(printer.printSwitchOnEnumAbstract.bind(expr, moduleType.args));
                case _:
            }
        }

        return items;
    }

    function createPostfixCompletionItem(data:PostfixCompletionItem, doc:TextDocument, replaceRange:Range):CompletionItem {
        var item:CompletionItem = {
            label: data.label,
            detail: data.detail,
            filterText: doc.getText(replaceRange) + " " + data.label, // https://github.com/Microsoft/vscode/issues/38982
            kind: Snippet,
            insertTextFormat: data.insertTextFormat,
            textEdit: {
                newText: data.insertText,
                range: replaceRange
            },
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
}

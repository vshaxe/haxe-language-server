package haxeLanguageServer.features.completion;

import haxeLanguageServer.protocol.Display;
import languageServerProtocol.Types.CompletionItem;
import haxeLanguageServer.features.completion.CompletionFeature.CompletionItemOrigin;

class PostfixCompletion {
    public function new() {}

    public function createItems<TMode,TItem>(mode:CompletionMode<TMode>, position:Position, doc:TextDocument):Array<CompletionItem> {
        var subject:FieldCompletionSubject<TItem>;
        switch (mode.kind) {
            case Field: subject = mode.args;
            case _: return [];
        }

        var type = subject.type;
        if (type == null) {
            return [];
        }

        var range = subject.range;
        var replaceRange:Range = {
            start: range.start,
            end: position
        };
        var expr = doc.getText(range);

        var items:Array<CompletionItem> = [];

        function add(data:PostfixCompletionItem) {
            items.push(createPostfixCompletionItem(data, doc, replaceRange));
        }

        switch (type.kind) {
            case TAbstract:
                var path = type.args.path;
                // TODO: unifiesWithInt, otherwise this won't work with abstract from / to's etc I guess
                if (path.name == "Int" && path.pack.length == 0) {
                    add({
                        label: "for",
                        detail: "for (i in 0...expr)",
                        insertText: 'for (i in 0...$expr) '
                    });
                }
            case _:
        }

        return items;
    }

    function createPostfixCompletionItem(data:PostfixCompletionItem, doc:TextDocument, replaceRange:Range):CompletionItem {
        return {
            label: data.label,
            detail: data.detail,
            filterText: doc.getText(replaceRange) + " " + data.label, // https://github.com/Microsoft/vscode/issues/38982
            kind: Keyword,
            textEdit: {
                newText: data.insertText,
                range: replaceRange
            },
            data: {
                origin: CompletionItemOrigin.Custom
            }
        }
    }
}

private typedef PostfixCompletionItem = {
    var label:String;
    var detail:String;
    var insertText:String;
}

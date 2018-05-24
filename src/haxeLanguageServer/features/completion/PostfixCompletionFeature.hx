package haxeLanguageServer.features.completion;

import haxeLanguageServer.protocol.Display;
import languageServerProtocol.Types.CompletionItem;
import haxeLanguageServer.features.completion.CompletionFeature.CompletionItemOrigin;

class PostfixCompletionFeature {
    public function new() {}

    public function createItems<TMode,TItem,TType>(mode:CompletionMode<TMode>, position:Position, textBefore:String, doc:TextDocument):Array<CompletionItem> {
        var subject:FieldCompletionSubject<TItem,TType>;
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

        // TODO: why is this type hint necessary to get struct field completion later on?
        var items:Array<CompletionItem> = [];
        switch (type.kind) {
            case TAbstract:
                var path = type.args.path;
                // TODO: unifiesWithInt, otherwise this won't work with abstract from / to's etc I guess
                if (path.name == "Int" && path.pack.length == 0) {
                    items.push({
                        label: "for",
                        detail: "for (i in 0...expr)",
                        filterText: doc.getText(replaceRange), // https://github.com/Microsoft/vscode/issues/38982
                        kind: Keyword,
                        textEdit: {
                            newText: 'for (i in 0...$expr) ',
                            range: replaceRange
                            // TODO: no struct field completion in here?
                        },
                        data: {origin: CompletionItemOrigin.Custom}
                    });
                }
            case _:
        }

        return items;
    }
}
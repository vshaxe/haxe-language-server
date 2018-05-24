package haxeLanguageServer.features;

import haxeLanguageServer.protocol.Display;
import haxeLanguageServer.protocol.Display.CompletionItem as HaxeCompletionItem;
import languageServerProtocol.Types.CompletionItem;
import haxeLanguageServer.features.CompletionFeature.CompletionItemOrigin;

class PostfixCompletionFeature {
    public function new() {}

    public function createItems<T1,T2,T3>(mode:CompletionMode<T1>, position:Position, textBefore:String):Array<CompletionItem> {
        var completingOn:HaxeCompletionItem<T2>;
        switch (mode.kind) {
            case Field: completingOn = mode.args;
            case _: return [];
        }

        var local:JsonLocal<T3>;
        switch (completingOn.kind) {
            case Local: local = completingOn.args;
            case _: return [];
        }

        // TODO: why is this type hint necessary to get struct field completion later on?
        var items:Array<CompletionItem> = [];

        // TODO: include replaceRange in the protocol?e
        var textBeforeRegex = ~/\b([a-zA-Z0-9.]+)$/;
        textBeforeRegex.match(textBefore);
        var matched = textBeforeRegex.matched(1);

        var expr = matched;
        var dotIndex = matched.lastIndexOf(".");
        if (dotIndex != -1) {
            expr = matched.substr(0, dotIndex);
        }

        var replaceRange:Range = {
            start: position.translate(0, -matched.length),
            // start: position.translate(0, -1),
            // start: position,
            end: position
        };

        var type = local.type;
        switch (type.kind) {
            case TAbstract:
                var path = type.args.path;
                // TODO: unifiesWithInt, otherwise this won't work with abstract from / to's etc I guess
                if (path.name == "Int" && path.pack.length == 0) {
                    items.push({
                        label: "for",
                        detail: "for (i in 0...expr)",
                        filterText: matched, // https://github.com/Microsoft/vscode/issues/38982
                        kind: Keyword,
                        textEdit: {
                            newText: 'for (i in 0...$expr) ',
                            range: replaceRange
                            // TODO: no struct field completion in here?
                        },
                        data: {origin: CompletionItemOrigin.Haxe}
                    });
                }
            case _:
        }

        return items;
    }
}
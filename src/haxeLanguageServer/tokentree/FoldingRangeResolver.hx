package haxeLanguageServer.tokentree;

import tokentree.TokenTree;
import languageServerProtocol.protocol.FoldingRange.FoldingRangeClientCapabilities;

class FoldingRangeResolver {
    final document:TextDocument;
    final lineFoldingOnly:Bool;

    public function new(document:TextDocument, capabilities:FoldingRangeClientCapabilities) {
        this.document = document;
        if (capabilities != null && capabilities.foldingRange != null) {
            lineFoldingOnly = capabilities.foldingRange.lineFoldingOnly;
        }
    }

    public function resolve():Array<FoldingRange> {
        var ranges:Array<FoldingRange> = [];
        function addRange(start:Position, end:Position, ?kind:FoldingRangeKind) {
            var range:FoldingRange = {
                startLine: start.line,
                endLine: end.line
            };
            if (!lineFoldingOnly) {
                range.startCharacter = start.character;
                range.endCharacter = end.character;
            }
            if (kind != null) {
                range.kind = kind;
            }
            ranges.push(range);
        }
        var tokens = document.tokens;
        tokens.tree.filterCallback(function(token:TokenTree, depth:Int) {
            switch (token.tok) {
                case BrOpen:
                    var range = tokens.getTreePos(token);
                    var start = document.positionAt(range.min);
                    var endLine = document.positionAt(range.max).line - 1;
                    if (endLine > start.line) {
                        var endCharacter = document.lineAt(endLine).length - 1;
                        addRange(start, {line: endLine, character: endCharacter});
                    }
                case Comment(_):
                    var range = tokens.getTreePos(token);
                    var start = document.positionAt(range.min);
                    var end = document.positionAt(range.max);
                    addRange(start, end, Comment);
                case _:
            }
            return GO_DEEPER;
        });
        return ranges;
    }
}

package haxeLanguageServer.tokentree;

import tokentree.TokenTree;
import languageServerProtocol.protocol.FoldingRange.FoldingRangeClientCapabilities;
import haxe.macro.Expr.Position;

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
        function addRange(range:Position, ?kind:FoldingRangeKind) {
            var start = document.positionAt(range.min);
            var end = document.positionAt(range.max);
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
        document.tokens.tree.filterCallback(function(token:TokenTree, depth:Int) {
            switch (token.tok) {
                case BrOpen:
                    addRange(document.tokens.getTreePos(token));
                case Comment(_):
                    addRange(document.tokens.getTreePos(token), Comment);
                case _:
            }
            return GO_DEEPER;
        });
        return ranges;
    }
}

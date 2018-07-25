package haxeLanguageServer.tokentree;

import tokentree.TokenTree;
using tokentree.TokenTreeAccessHelper;
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
        function add(start:Position, end:Position, ?kind:FoldingRangeKind) {
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

        function addRange(range:haxe.macro.Expr.Position, ?kind:FoldingRangeKind) {
            var start = document.positionAt(range.min);
            var end = document.positionAt(range.max);
            add(start, end, kind);
        }

        var firstImport = null;
        var lastImport = null;
        var conditionalStack = [];
        var tokens = document.tokens;
        tokens.tree.filterCallback(function(token:TokenTree, _) {
            switch (token.tok) {
                case BrOpen:
                    var range = tokens.getTreePos(token);
                    var start = document.positionAt(range.min);
                    var endLine = document.positionAt(range.max).line - 1;
                    if (endLine > start.line) {
                        var endCharacter = document.lineAt(endLine).length - 1;
                        add(start, {line: endLine, character: endCharacter});
                    }

                case Comment(_):
                    addRange(tokens.getTreePos(token), Comment);

                case Kwd(KwdImport), Kwd(KwdUsing):
                    if (firstImport == null) {
                        firstImport = token;
                    }
                    lastImport = token;

                case Sharp(sharp):
                    // everything except `#if` ends a range / adds a folding marker
                    if (sharp == "else" || sharp == "elseif" || sharp == "end") {
                        var start = conditionalStack.pop();
                        var pos = tokens.getPos(token);
                        var endLine = document.positionAt(pos.max).line - 1;
                        if (start != null && endLine > start.line) {
                            var endCharacter = document.lineAt(endLine).length - 1;
                            add(start, {line: endLine, character: endCharacter});
                        }
                    }

                    // everything except `#end` starts a range
                    if (sharp == "if" || sharp == "else" || sharp == "elseif") {
                        var pClose = token.access().firstChild().is(POpen).lastChild().is(PClose).token;
                        var pos = if (pClose == null) tokens.getPos(token) else tokens.getPos(pClose);
                        var start = document.positionAt(pos.max);
                        start.character++;
                        conditionalStack.push(start);
                    }

                case _:
            }
            return GO_DEEPER;
        });

        if (lastImport != null && firstImport != lastImport) {
            var start = tokens.getPos(firstImport);
            var end = tokens.getTreePos(lastImport);
            addRange({file: start.file, min: start.min, max: end.max}, Imports);
        }

        return ranges;
    }
}

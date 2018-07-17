package haxeLanguageServer.tokentree;

import tokentree.TokenTree;

class DocumentSymbolsResolver {
    final document:TextDocument;
    final symbols = new Array<DocumentSymbol>();

    public function new(document:TextDocument) {
        this.document = document;
    }

    public function resolve():Array<DocumentSymbol> {
        var previousDepth = 0;
        var parentStack = [symbols];
        document.tokenTree.filterCallback((token, depth) -> {
            if (depth > previousDepth) {
                parentStack[depth] = parentStack[depth - 1];
            } else if (depth < previousDepth) {
                while (parentStack.length - 1 > depth) {
                    parentStack.pop();
                }
            }

            var result = switch (token.tok) {
                case Const(CIdent(ident)):
                    function add(kind:SymbolKind) {
                        var symbol = {
                            name: ident,
                            detail: "",
                            kind: kind,
                            range: positionToRange(token.parent.getPos()),
                            selectionRange: positionToRange(token.pos),
                            children: []
                        };
                        parentStack[depth].push(symbol);
                        parentStack[depth] = symbol.children;
                    }
                    switch (token.parent.tok) {
                        case Kwd(KwdClass):
                            add(Class);
                        case Kwd(KwdFunction):
                            add(Method);
                        case Kwd(KwdVar):
                            add(Field);
                        case _:
                    }
                    GO_DEEPER;
                case _:
                    GO_DEEPER;
            }
            previousDepth = depth;
            result;
        });
        return symbols;
    }

    function positionToRange(pos:haxe.macro.Expr.Position):Range {
        return {
            start: document.positionAt(pos.min),
            end: document.positionAt(pos.max)
        };
    }
}

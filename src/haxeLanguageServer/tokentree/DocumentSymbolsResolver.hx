package haxeLanguageServer.tokentree;

import tokentree.TokenTree;

class DocumentSymbolsResolver {
    final document:TextDocument;
    final tokenTree:TokenTree;
    final symbols = new Array<DocumentSymbol>();

    public function new(document:TextDocument, tokenTree:TokenTree) {
        this.document = document;
        this.tokenTree = tokenTree;
    }

    public function resolve():Array<DocumentSymbol> {
        var previousDepth = 0;
        var parentStack = [symbols];
        tokenTree.filterCallback((token, depth) -> {
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
                        var symbol = createSymbol(ident, token.parent, kind);
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

    function createSymbol(name:String, token:TokenTree, kind:SymbolKind):DocumentSymbol {
        return {
            name: name,
            detail: "",
            kind: kind,
            range: positionToRange(token.getPos()),
            selectionRange: positionToRange(token.pos),
            children: []
        };
    }

    function positionToRange(pos:haxe.macro.Expr.Position):Range {
        return {
            start: document.positionAt(pos.min),
            end: document.positionAt(pos.max)
        };
    }
}

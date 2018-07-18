package haxeLanguageServer.tokentree;

import tokentree.TokenTree;
using tokentree.TokenTreeAccessHelper;
using tokentree.utils.TokenTreeCheckUtils;

class DocumentSymbolsResolver {
    final document:TextDocument;

    public function new(document:TextDocument) {
        this.document = document;
    }

    public function resolve():Array<DocumentSymbol> {
        var previousDepth = 0;
        var parentPerDepth = [new Array<DocumentSymbol>()];

        document.tokenTree.filterCallback(function(token:TokenTree, depth:Int) {
            if (depth > previousDepth) {
                if (parentPerDepth[depth] == null) {
                    parentPerDepth[depth] = parentPerDepth[depth - 1];
                }
            } else if (depth < previousDepth) {
                while (parentPerDepth.length - 1 > depth) {
                    parentPerDepth.pop();
                }
            }

            function add(kind:SymbolKind) {
                var identToken = token.access().firstChild().token;
                var name = null;
                if (identToken == null) {
                    identToken = token;
                    name = '<${identToken.tok}>';
                } else {
                    name = switch (identToken.tok) {
                        case Const(CIdent(ident)): ident;
                        case _: null;
                    }
                }
                var symbol = {
                    name: name,
                    detail: "",
                    kind: kind,
                    range: positionToRange(token.getPos()),
                    selectionRange: positionToRange(identToken.pos),
                    children: []
                };
                parentPerDepth[depth].push(symbol);
                parentPerDepth[depth + 1] = symbol.children;
            }

            switch (token.tok) {
                case At:
                    // @:enum has Kwd(KwdEnum), make sure to ignore that
                    return SKIP_SUBTREE;

                case Kwd(KwdClass):
                    add(Class);
                case Kwd(KwdAbstract):
                    if (token.isTypeEnumAbstract()) {
                        add(Enum);
                    } else {
                        add(Class);
                    }
                case Kwd(KwdInterface):
                    add(Interface);
                case Kwd(KwdTypedef):
                    add(Struct);
                case Kwd(KwdEnum) if (!token.isTypeEnumAbstract()):
                    add(Enum);

                case Kwd(KwdFunction):
                    add(Method);
                case Kwd(KwdVar):
                    add(Field);
                case _:
            }

            previousDepth = depth;
            return GO_DEEPER;
        });
        return parentPerDepth[0];
    }

    function positionToRange(pos:haxe.macro.Expr.Position):Range {
        return {
            start: document.positionAt(pos.min),
            end: document.positionAt(pos.max)
        };
    }
}

package haxeLanguageServer.tokentree;

import tokentree.TokenTree;
using tokentree.TokenTreeAccessHelper;
using tokentree.utils.TokenTreeCheckUtils;
using tokentree.utils.FieldUtils;

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

            function add(kind:SymbolKind, ?name:String) {
                if (name == null) {
                    name = token.getName();
                }
                if (name == null) {
                    name = "";
                }
                var selectedToken = token.access().firstChild().or(token);
                var symbol = {
                    name: name,
                    detail: "",
                    kind: kind,
                    range: positionToRange(token.getPos()),
                    selectionRange: positionToRange(selectedToken.pos),
                    children: []
                };
                parentPerDepth[depth].push(symbol);
                parentPerDepth[depth + 1] = symbol.children;
            }

            switch (token.tok) {
                case Kwd(KwdClass):
                    add(Class);
                case Kwd(KwdInterface):
                    add(Interface);
                case Kwd(KwdAbstract):
                    add(if (token.isTypeEnumAbstract()) Enum else Class);
                case Kwd(KwdTypedef):
                    add(if (token.isTypeStructure()) Struct else Interface);
                case Kwd(KwdEnum):
                    if (token.isTypeEnum()) {
                        add(Enum);
                    }

                case Kwd(KwdFunction), Kwd(KwdVar):
                    switch (token.getFieldType(PRIVATE)) {
                        case FUNCTION(name, _, _, _, _, _, _):
                            add(if (name == "new") Constructor else Method, name);
                        case VAR(name, _, _, isInline, _, _):
                            add(if (isInline) Constant else Variable, name);
                        case PROP(name, _, _, _, _):
                            add(Property, name);
                        case UNKNOWN:
                    }
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

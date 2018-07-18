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

            function add(token:TokenTree, kind:SymbolKind, ?name:String) {
                if (name == null) {
                    name = token.getName();
                }
                if (name == null) {
                    name = "";
                }
                var selectedToken = token.access().firstChild().or(token);
                if (selectedToken.inserted) {
                    return; // don't want to show `autoInsert` vars and similar
                }
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
                    var name = token.getName();
                    if (name == null && token.isTypeMacroClass()) {
                        name = "<macro class>";
                    }
                    add(token, Class, name);
                case Kwd(KwdInterface):
                    add(token, Interface);
                case Kwd(KwdAbstract):
                    add(token, if (token.isTypeEnumAbstract()) Enum else Class);
                case Kwd(KwdTypedef):
                    add(token, if (token.isTypeStructure()) Struct else Interface);
                case Kwd(KwdEnum):
                    if (token.isTypeEnum()) {
                        add(token, Enum);
                    }

                case Kwd(KwdFunction), Kwd(KwdVar):
                    switch (token.getFieldType(PRIVATE)) {
                        case FUNCTION(name, _, _, _, _, _, _):
                            if (name == null) {
                                name = "<anonymous function>";
                            }
                            var kind:SymbolKind = if (name == "new") {
                                Constructor;
                            } else if (token.isOperatorFunction()) {
                                Operator;
                            } else {
                                Method;
                            }
                            add(token, kind, name);
                        case VAR(name, _, _, isInline, _, _):
                            add(token, if (isInline) Constant else Variable, name);
                        case PROP(name, _, _, _, _):
                            add(token, Property, name);
                        case UNKNOWN:
                    }
                case Kwd(KwdFor), Kwd(KwdCatch):
                    var ident = token.access().firstChild().is(POpen).firstChild().isCIdent().token;
                    if (ident != null) {
                        add(ident, Variable);
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

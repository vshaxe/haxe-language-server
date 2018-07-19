package haxeLanguageServer.tokentree;

import haxeLanguageServer.protocol.Display.DisplayModuleTypeKind;
import tokentree.TokenTree;
using tokentree.TokenTreeAccessHelper;
using tokentree.utils.TokenTreeCheckUtils;
using tokentree.utils.FieldUtils;

/** (_not_ a video game level, simn) **/
private enum SymbolLevel {
    Type;
    Field;
    Expression;
}

class DocumentSymbolsResolver {
    final document:TextDocument;

    public function new(document:TextDocument) {
        this.document = document;
    }

    public function resolve():Array<DocumentSymbol> {
        var previousDepth = 0;
        var parentPerDepth = [{level: Type, symbols: new Array<DocumentSymbol>()}];
        var type:DisplayModuleTypeKind;

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

            function add(token:TokenTree, kind:SymbolKind, level:SymbolLevel, ?name:String) {
                if (name == null) {
                    name = token.getName();
                }
                if (name == null) {
                    return;
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
                parentPerDepth[depth].symbols.push(symbol);
                parentPerDepth[depth + 1] = {level: level, symbols: symbol.children};
            }

            switch (token.tok) {
                case Kwd(KwdClass):
                    var name = token.getName();
                    if (name == null && token.isTypeMacroClass()) {
                        name = "<macro class>";
                    }
                    add(token, Class, Type, name);
                    type = Class;
                case Kwd(KwdInterface):
                    add(token, Interface, Type);
                    type = Interface;
                case Kwd(KwdAbstract):
                    var isEnumAbstract = token.isTypeEnumAbstract();
                    add(token, if (isEnumAbstract) Enum else Class, Type);
                    type = if (isEnumAbstract) EnumAbstract else Class;
                case Kwd(KwdTypedef):
                    var isStructure = token.isTypeStructure();
                    add(token, if (isStructure) Struct else Interface, Type);
                    type = if (isStructure) Struct else TypeAlias;
                case Kwd(KwdEnum):
                    if (token.isTypeEnum()) {
                        add(token, Enum, Type);
                        type = Enum;
                    }

                case Kwd(KwdFunction), Kwd(KwdVar), Kwd(KwdFinal):
                    var parentLevel = parentPerDepth[depth].level;
                    var currentLevel = switch (parentLevel) {
                        case Type: Field;
                        case Field, Expression: Expression;
                    };
                    switch (token.getFieldType(PRIVATE)) {
                        case FUNCTION(name, _, _, _, _, _, _):
                            if (name == null) {
                                name = "<anonymous function>";
                            }
                            var kind:SymbolKind = if (name == "new") {
                                Constructor;
                            } else if (token.isOperatorFunction() && (type == Abstract || type == EnumAbstract)) {
                                Operator;
                            } else {
                                Method;
                            }
                            add(token, kind, currentLevel, name);
                        case VAR(name, _, isStatic, isInline, _, _):
                            var kind:SymbolKind = if (type == EnumAbstract && !isStatic) {
                                EnumMember;
                            } else if (isInline) {
                                Constant;
                            } else if (parentLevel == Type) {
                                Field;
                            } else {
                                Variable;
                            }
                            add(token, kind, currentLevel, name);
                        case PROP(name, _, _, _, _):
                            add(token, Property, currentLevel, name);
                        case UNKNOWN:
                    }
                case Kwd(KwdFor), Kwd(KwdCatch):
                    var ident = token.access().firstChild().is(POpen).firstChild().isCIdent().token;
                    if (ident != null) {
                        add(ident, Variable, Expression);
                    }
                case Const(CIdent(_)) if (type != null):
                    switch (type) {
                        case Enum:
                            if (token.access().parent().is(BrOpen).exists()) {
                                add(token, EnumMember, Field);
                            }
                        case Struct:
                            var parent = token.access().parent();
                            if (parent.is(Question).exists()) {
                                parent = parent.parent();
                            }
                            if (parent.is(BrOpen).exists() && token.access().firstChild().is(DblDot).exists()) {
                                add(token, Field, Field);
                            }
                        case _:
                    }
                case _:
            }

            previousDepth = depth;
            return GO_DEEPER;
        });
        return parentPerDepth[0].symbols;
    }

    function positionToRange(pos:haxe.macro.Expr.Position):Range {
        return {
            start: document.positionAt(pos.min),
            end: document.positionAt(pos.max)
        };
    }
}

package haxeLanguageServer.tokentree;

import haxeLanguageServer.protocol.Display.DisplayModuleTypeKind;
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
        var stack = new SymbolStack();
        document.tokens.tree.filterCallback(function(token:TokenTree, depth:Int) {
            stack.depth = depth;
            function add(token:TokenTree, kind:SymbolKind, level:SymbolLevel, ?name:String, ?opensScope:Bool) {
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
                if (opensScope == null) {
                    opensScope = true;
                }
                var symbol:DocumentSymbol = {
                    name: name,
                    detail: "",
                    kind: kind,
                    range: positionToRange(document.tokens.getTreePos(token)),
                    selectionRange: positionToRange(document.tokens.getPos(selectedToken)),
                    children: []
                };
                if (token.isDeprecated()) {
                    symbol.deprecated = true;
                }
                stack.addSymbol(level, symbol, opensScope);
            }

            switch (token.tok) {
                case Kwd(KwdClass):
                    var name = token.getName();
                    if (name == null && token.isTypeMacroClass()) {
                        name = "<macro class>";
                    }
                    add(token, Class, Type(Class), name);

                case Kwd(KwdInterface):
                    add(token, Interface, Type(Interface));

                case Kwd(KwdAbstract):
                    if (token.isTypeEnumAbstract()) {
                        add(token, Enum, Type(EnumAbstract));
                    } else {
                        add(token, Class, Type(Abstract));
                    }

                case Kwd(KwdTypedef):
                    if (token.isTypeStructure()) {
                        add(token, Struct, Type(Struct));
                    } else {
                        add(token, Interface, Type(TypeAlias));
                    }

                case Kwd(KwdEnum):
                    if (token.isTypeEnum()) {
                        add(token, Enum, Type(Enum));
                    }

                case Kwd(KwdFunction), Kwd(KwdVar), Kwd(KwdFinal):
                    var currentLevel = switch (stack.level) {
                        case Root, Type(_): Field;
                        case Field, Expression: Expression;
                    };
                    switch (token.getFieldType(PRIVATE)) {
                        case FUNCTION(name, _, _, _, _, _, _):
                            if (name == null) {
                                name = "<anonymous function>";
                            }
                            var type = stack.getParentTypeKind();
                            var kind:SymbolKind = if (name == "new") {
                                Constructor;
                            } else if (token.isOperatorFunction() && (type == Abstract || type == EnumAbstract)) {
                                Operator;
                            } else {
                                Method;
                            }
                            add(token, kind, currentLevel, name);

                        case VAR(name, _, isStatic, isInline, _, _):
                            if (currentLevel == Expression) {
                                var children = token.children;
                                if (children != null) {
                                    // at expression level, we might have a multi-var expr (`var a, b, c;`)
                                    for (i in 0...children.length) {
                                        var opensScope = i == children.length - 1;
                                        add(children[i], Variable, currentLevel, opensScope);
                                    }
                                }
                            } else {
                                var type = stack.getParentTypeKind();
                                var kind:SymbolKind = if (type == EnumAbstract && !isStatic) {
                                    EnumMember;
                                } else if (isInline) {
                                    Constant;
                                } else {
                                    Field;
                                }
                                add(token, kind, currentLevel, name);
                            }

                        case PROP(name, _, _, _, _):
                            add(token, Property, currentLevel, name);

                        case UNKNOWN:
                    }

                case Kwd(KwdFor), Kwd(KwdCatch):
                    var ident = token.access().firstChild().is(POpen).firstChild().isCIdent().token;
                    if (ident != null) {
                        add(ident, Variable, Expression, false);
                    }

                case Const(CIdent(_)):
                    switch (stack.getParentTypeKind()) {
                        case null:
                        case Enum:
                            if (token.access().parent().is(BrOpen).exists()) {
                                add(token, EnumMember, Field);
                            }
                        case Struct:
                            var parent = token.access().parent();
                            if (parent.is(Question).exists()) {
                                parent = parent.parent();
                            }
                            if (parent.is(BrOpen).exists()) {
                                add(token, Field, Field);
                            }
                        case _:
                    }

                case _:
            }
            return GO_DEEPER;
        });
        return stack.root;
    }

    function positionToRange(pos:haxe.macro.Expr.Position):Range {
        return {
            start: document.positionAt(pos.min),
            end: document.positionAt(pos.max)
        };
    }
}

/** (_not_ a video game level, simn) **/
private enum SymbolLevel {
    Root;
    Type(kind:DisplayModuleTypeKind);
    Field;
    Expression;
}

private abstract SymbolStack(Array<{level:SymbolLevel, symbols:Array<DocumentSymbol>}>) {
    public var depth(get,set):Int;
    inline function get_depth() return this.length - 1;
    function set_depth(newDepth:Int) {
        if (newDepth > depth) {
            // only accounts for increases of 1
            if (this[newDepth] == null) {
                this[newDepth] = this[newDepth - 1];
            }
        } else if (newDepth < depth) {
            while (depth > newDepth) {
                this.pop();
            }
        }
        return depth;
    }

    public var level(get,never):SymbolLevel;
    inline function get_level() return this[depth].level;

    public var root(get,never):Array<DocumentSymbol>;
    inline function get_root() return this[0].symbols;

    public function new() {
        this = [{level: Root, symbols: new Array<DocumentSymbol>()}];
    }

    public function addSymbol(level:SymbolLevel, symbol:DocumentSymbol, opensScope:Bool) {
        this[depth].symbols.push(symbol);
        if (opensScope) {
            this[depth + 1] = {level: level, symbols: symbol.children};
        }
    }

    public function getParentTypeKind():DisplayModuleTypeKind {
        var i = depth;
        while (i-- > 0) {
            switch (this[i].level) {
                case Type(kind):
                    return kind;
                case _:
            }
        }
        return null;
    }
}

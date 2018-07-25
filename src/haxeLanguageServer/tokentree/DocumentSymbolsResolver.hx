package haxeLanguageServer.tokentree;

import haxeLanguageServer.protocol.Display.DisplayModuleTypeKind;
import tokentree.TokenTree;
using tokentree.TokenTreeAccessHelper;
using tokentree.utils.TokenTreeCheckUtils;
using tokentree.utils.FieldUtils;

class DocumentSymbolsResolver {
    final document:TextDocument;
    final includeDocComments:Bool;

    public function new(document:TextDocument, includeDocComments:Bool) {
        this.document = document;
        this.includeDocComments = includeDocComments;
    }

    public function resolve():Array<DocumentSymbol> {
        var stack = new SymbolStack();
        var tokens = document.tokens;
        tokens.tree.filterCallback(function(token:TokenTree, depth:Int) {
            stack.depth = depth;
            function add(token:TokenTree, kind:SymbolKind, level:SymbolLevel, ?name:String, ?opensScope:Bool) {
                var nameToken = token.getNameToken();
                if (nameToken == null && name != null) {
                    nameToken = token;
                }
                if (nameToken == null || nameToken.inserted) {
                    return; // don't want to show `autoInsert` vars and similar
                }
                if (name == null) {
                    name = nameToken.getName();
                }
                if (opensScope == null) {
                    opensScope = true;
                }
                var range = tokens.getTreePos(token);
                if (level != Expression && includeDocComments) {
                    var docComment = token.getDocComment();
                    if (docComment != null) {
                        var docCommentPos = tokens.getPos(docComment);
                        range = {file: range.file, min: docCommentPos.min, max: range.max};
                    }
                }
                var symbol:DocumentSymbol = {
                    name: name,
                    detail: "",
                    kind: kind,
                    range: positionToRange(range),
                    selectionRange: positionToRange(tokens.getPos(nameToken))
                };
                if (token.isDeprecated()) {
                    symbol.deprecated = true;
                }
                stack.addSymbol(level, symbol, opensScope);
            }

            switch (token.tok) {
                case Kwd(KwdClass):
                    var name = token.getNameToken().getName();
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
                                        var token = if (i == 0) token else children[i];
                                        add(token, Variable, currentLevel, opensScope);
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
        hideIgnoredVariables(stack.root);
        return stack.root.children;
    }

    function hideIgnoredVariables(symbol:DocumentSymbol) {
        if (symbol.children == null) {
            return;
        }
        var i = symbol.children.length;
        while (i-- > 0) {
            var child = symbol.children[i];
            if (child.children == null && child.name == "_") {
                symbol.children.remove(child);
            } else {
                hideIgnoredVariables(child);
            }
        }
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

private abstract SymbolStack(Array<{level:SymbolLevel, symbol:DocumentSymbol}>) {
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

    public var root(get,never):DocumentSymbol;
    inline function get_root() return this[0].symbol;

    public function new() {
        this = [{
            level: Root,
            symbol: {
                name: "root",
                kind: Module,
                range: null,
                selectionRange: null,
                children: []
            }
        }];
    }

    public function addSymbol(level:SymbolLevel, symbol:DocumentSymbol, opensScope:Bool) {
        var parentSymbol = this[depth].symbol;
        if (parentSymbol.children == null) {
            parentSymbol.children = [];
        }
        parentSymbol.children.push(symbol);

        if (opensScope) {
            this[depth + 1] = {level: level, symbol: symbol};
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

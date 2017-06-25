package haxeLanguageServer.hxParser;

import hxParser.WalkStack;
import hxParser.ParseTree;
import haxeLanguageServer.hxParser.PositionAwareWalker.Scope;
using hxParser.WalkStackTools;
using Lambda;

private typedef DeclInfo = {
    var scope:Scope;
    var isCaptureVariable:Bool;
}

class RenameResolver extends PositionAwareWalker {
    public var edits(default,null):Array<TextEdit> = [];

    var declaration:Range;
    var newName:String;

    var rangeConsumers = new Map<Token, Range->Void>();

    var declarationInfo:DeclInfo;
    var declarationInScope = false;
    var declarationIdentifier:String;

    var inStaticFunction:Bool = false;
    var typeName:String;

    var shadowingDecls:Array<DeclInfo> = [];
    var newIdentShadowingDecls:Array<DeclInfo> = [];

    public function new(declaration:Range, newName:String) {
        this.declaration = declaration;
        this.newName = newName;
    }

    override function processToken(token:Token, stack:WalkStack) {
        function getRange():Range {
            return {
                start: {line: line, character: character},
                end: {line: line, character: character + token.text.length}
            };
        }

        // are we still in the declaration scope?
        if (declarationInScope && !declarationInfo.scope.contains(scope)) {
            declarationInScope = false;
        }

        // have we found the declaration yet? (assume that usages can only be after the declaration)
        if (!declarationInScope && declaration.isEqual(getRange())) {
            declarationInScope = true;
            declarationInfo = {
                scope: scope.copy(),
                isCaptureVariable: isCaptureVariable(stack)
            };
            declarationIdentifier = token.text;
            edits.push({
                range: declaration,
                newText: newName
            });
        }

        if (rangeConsumers[token] != null) {
            rangeConsumers[token](getRange());
            rangeConsumers[token] = null;
        }

        super.processToken(token, stack);
    }

    function checkShadowing(token:Token, isCaptureVariable:Bool = false) {
        if (!declarationInScope) {
            return;
        }

        function addShadowingDecl(decls:Array<DeclInfo>) {
            var last = decls[decls.length - 1];
            if (decls.length > 0 && isCaptureVariable && isCaptureVariableInSameScope(last, scope)) {
                // capture vars can't shadow other capture vars on same scope
                return;
            }

            decls.push({
                scope: scope.copy(),
                isCaptureVariable: isCaptureVariable
            });
        }

        if (declarationIdentifier == token.text) {
            addShadowingDecl(shadowingDecls);
        } else if (newName == token.text) {
            addShadowingDecl(newIdentShadowingDecls);
        }
    }

    override function closeScope() {
        super.closeScope();
        updateShadowingDecls(shadowingDecls);
        updateShadowingDecls(newIdentShadowingDecls);
    }

    function updateShadowingDecls(decls:Array<DeclInfo>) {
        var i = decls.length;
        while (i-- > 0) {
            if (!decls[i].scope.contains(scope)) {
                decls.pop();
            } else {
                break;
            }
        }
    }

    override function walkNConst_PConstIdent(ident:Token, stack:WalkStack) {
        handleIdent(ident.text, ident, stack);
        super.walkNConst_PConstIdent(ident, stack);
    }

    override function walkExpr_EDollarIdent(ident:Token, stack:WalkStack) {
        handleIdent(ident.text.substr(1), ident, stack);
        super.walkExpr_EDollarIdent(ident, stack);
    }

    override function walkNDotIdent_PDotIdent(name:Token, stack:WalkStack) {
        if (name.text.startsWith(".$")) {
            handleIdent(name.text.substr(2), name, stack);
        }
        super.walkNDotIdent_PDotIdent(name, stack);
    }

    function isCaptureVariable(stack:WalkStack) {
        return stack.find(stack -> stack.match(Edge("patterns", Node(Case_Case(_, _, _, _, _), _))));
    }

    function isCaptureVariableInSameScope(decl:DeclInfo, scope:Scope) {
        return decl.isCaptureVariable && decl.scope.equals(scope);
    }

    function handleIdent(identText:String, ident:Token, stack:WalkStack) {
        // assume that lowercase idents in `case` are capture vars
        var firstChar = identText.charAt(0);
        if (firstChar == firstChar.toLowerCase() && isCaptureVariable(stack)
                && (declarationInfo == null || !isCaptureVariableInSameScope(declarationInfo, scope))) {
            checkShadowing(ident, true);
        } else if (declarationInScope) {
            if (declarationIdentifier == identText && shadowingDecls.length == 0) {
                rangeConsumers[ident] = function(range) {
                    edits.push({
                        range: range,
                        newText: ident.text.replace(identText, newName)
                    });
                }
            } else if (identText == newName && newIdentShadowingDecls.length == 0) {
                // avoid conflicts
                rangeConsumers[ident] = function(range) {
                    var prefix = if (inStaticFunction) typeName else "this";
                    edits.push({
                        range: range,
                        newText: '$prefix.$newName'
                    });
                }
            }
        }
    }

    override function walkExpr_EVar(varKeyword:Token, decl:VarDecl, stack:WalkStack) {
        checkShadowing(decl.name);
        super.walkExpr_EVar(varKeyword, decl, stack);
    }

    override function walkVarDecl(node:VarDecl, stack:WalkStack) {
        checkShadowing(node.name);
        super.walkVarDecl(node, stack);
    }

    override function walkFunctionArgument(node:FunctionArgument, stack:WalkStack) {
        checkShadowing(node.name);
        super.walkFunctionArgument(node, stack);
    }

    override function walkExpr_EIn(exprLeft:Expr, inKeyword:Token, exprRight:Expr, stack:WalkStack) {
        switch (exprLeft) {
            case EConst(PConstIdent(variable)):
                checkShadowing(variable);
            case _:
        }
        super.walkExpr_EIn(exprLeft, inKeyword, exprRight, stack);
    }

    override function walkCatch(node:Catch, stack:WalkStack) {
        scope.push(node.catchKeyword);
        checkShadowing(node.ident);
        super.walkCatch(node, stack);
        closeScope();
    }

    override function walkClassField_Function(annotations:NAnnotations, modifiers:Array<FieldModifier>, functionKeyword:Token, name:Token, params:Null<TypeDeclParameters>, parenOpen:Token, args:Null<CommaSeparated<FunctionArgument>>, parenClose:Token, typeHint:Null<TypeHint>, expr:MethodExpr, stack:WalkStack) {
        inStaticFunction = modifiers.find(modifier -> modifier.match(Static(_))) != null;
        super.walkClassField_Function(annotations, modifiers, functionKeyword, name, params, parenOpen, args, parenClose, typeHint, expr, stack);
    }

    override function walkEnumDecl(node:EnumDecl, stack:WalkStack) {
        typeName = node.name.text;
        super.walkEnumDecl(node, stack);
    }

    override function walkAbstractDecl(node:AbstractDecl, stack:WalkStack) {
        typeName = node.name.text;
        super.walkAbstractDecl(node, stack);
    }

    override function walkClassDecl(node:ClassDecl, stack:WalkStack) {
        typeName = node.name.text;
        super.walkClassDecl(node, stack);
    }

    override function walkTypedefDecl(node:TypedefDecl, stack:WalkStack) {
        typeName = node.name.text;
        super.walkTypedefDecl(node, stack);
    }
}
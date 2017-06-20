package haxeLanguageServer.hxParser;

import hxParser.WalkStack;
import hxParser.ParseTree;
import haxeLanguageServer.hxParser.PositionAwareWalker.Scope;
using hxParser.WalkStackTools;
using Lambda;

class LocalUsageResolver extends PositionAwareWalker {
    public var usages(default,null):Array<Range> = [];

    var declaration:Range;
    var usageTokens:Array<Token> = [];

    var declarationScope:Scope;
    var declarationInScope = false;
    var declarationIdentifier:String;

    var shadowingDecls:Array<Scope> = [];

    public function new(declaration:Range) {
        this.declaration = declaration;
    }

    override function processToken(token:Token, stack:WalkStack) {
        function getRange():Range {
            return {
                start: {line: line, character: character},
                end: {line: line, character: character + token.text.length}
            };
        }

        // are we still in the declaration scope?
        if (declarationInScope && !declarationScope.contains(scope)) {
            declarationInScope = false;
        }

        // have we found the declaration yet? (assume that usages can only be after the declaration)
        if (!declarationInScope && declaration.isEqual(getRange())) {
            declarationInScope = true;
            declarationScope = scope.copy();
            declarationIdentifier = token.text;
            usages.push(declaration);
        }

        if (usageTokens.has(token)) {
            usages.push(getRange());
            usageTokens.remove(token);
        }

        super.processToken(token, stack);
    }

    function checkShadowing(token:Token) {
        if (declarationInScope && declarationIdentifier == token.text) {
            shadowingDecls.push(scope.copy());
        }
    }

    override function closeScope() {
        super.closeScope();
        var i = shadowingDecls.length;
        while (i-- > 0) {
            if (!shadowingDecls[i].contains(scope)) {
                shadowingDecls.pop();
            } else {
                break;
            }
        }
    }

    override function walkNConst_PConstIdent(ident:Token, stack:WalkStack) {
        // assume that lowercase idents in `case` are capture vars
        var firstChar = ident.text.charAt(0);
        if (firstChar == firstChar.toLowerCase() && stack.find(stack -> stack.match(Node(Case_Case(_, _, _, _, _), _)))) {
            checkShadowing(ident);
        } else if (declarationInScope && declarationIdentifier == ident.text && shadowingDecls.length == 0) {
            usageTokens.push(ident);
        }
        super.walkNConst_PConstIdent(ident, stack);
    }

    override function walkExpr_EVar(varKeyword:Token, decl:VarDecl, stack:WalkStack) {
        checkShadowing(decl.name);
        super.walkExpr_EVar(varKeyword, decl, stack);
    }

    override function walkVarDecl(node:VarDecl, stack:WalkStack) {
        checkShadowing(node.name);
        super.walkVarDecl(node, stack);
    }

    override function walkExpr_EIn(exprLeft:Expr, inKeyword:Token, exprRight:Expr, stack:WalkStack) {
        switch (exprLeft) {
            case EConst(PConstIdent(variable)):
                checkShadowing(variable);
            case _:
        }
        super.walkExpr_EIn(exprLeft, inKeyword, exprRight, stack);
    }

    override function walkFunctionArgument(node:FunctionArgument, stack:WalkStack) {
        checkShadowing(node.name);
        super.walkFunctionArgument(node, stack);
    }
}
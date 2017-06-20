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
        if (declarationInScope) {
            if (!declarationScope.contains(scope)) {
                declarationInScope = false;
            }

            // shadowing?
            if (declarationIdentifier == token.text && stack.match(Edge(_, Node(VarDecl(_), _)))) {
                declarationInScope = false;
            }
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

    override function walkNConst_PConstIdent(ident:Token, stack:WalkStack) {
        if (declarationInScope && declarationIdentifier == ident.text) {
            usageTokens.push(ident);
        }
        super.walkNConst_PConstIdent(ident, stack);
    }
}
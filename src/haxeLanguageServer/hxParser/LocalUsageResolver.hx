package haxeLanguageServer.hxParser;

import hxParser.WalkStack;
import hxParser.ParseTree;
using hxParser.WalkStackTools;

class LocalUsageResolver extends PositionAwareWalker {
    public var usages(default,null):Array<Range> = [];

    var declaration:Range;
    var usageTokens:Array<Token> = [];

    var declarationInScope = false;
    var declarationStack:WalkStack;
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

        if (!declarationInScope && declaration.isEqual(getRange())) {
            declarationInScope = true;
            declarationStack = stack;
            declarationIdentifier = token.text;
            usages.push(declaration);
        }

        if (usageTokens.indexOf(token) != -1) {
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
package haxeLanguageServer.hxParser;

import hxParser.WalkStack;
import hxParser.ParseTree;
import hxParser.StackAwareWalker;

class PositionAwareWalker extends StackAwareWalker {
    var line:Int = 0;
    var character:Int = 0;

    override function walkToken(token:Token, stack:WalkStack) {
        processTrivia(token.leadingTrivia);
        if (token.appearsInSource()) processToken(token);
        processTrivia(token.trailingTrivia);
    }

    function processToken(token:Token) {
        character += token.text.length;
    }

    function processTrivia(trivias:Array<Trivia>) {
        for (trivia in trivias) {
            var newlines = trivia.text.occurrences("\n");
            if (newlines > 0) {
                line += newlines;
                character = 0;
            } else {
                character += trivia.text.length;
            }
        }
    }

    override function walkLiteral_PLiteralString(s:StringToken, stack:WalkStack) {
        var string = switch (s) {
            case DoubleQuote(token) | SingleQuote(token): token.text;
        }
        line += string.occurrences("\n");
        super.walkLiteral_PLiteralString(s, stack);
    }
}
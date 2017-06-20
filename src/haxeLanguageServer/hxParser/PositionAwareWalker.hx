package haxeLanguageServer.hxParser;

import hxParser.WalkStack;
import hxParser.ParseTree;
import hxParser.StackAwareWalker;

@:forward(push, pop)
abstract Scope(Array<Token>) {
    public function new(?tokens:Array<Token>) {
        this = if (tokens == null) [] else tokens;
    }

    public function copy():Scope {
        return new Scope(this.copy());
    }

    public function contains(scope:Scope):Bool {
        var other:Array<Token> = cast scope;
        if (this.length > other.length) {
            return false;
        }
        for (i in 0...this.length) {
            if (other[i] != this[i]) {
                return false;
            }
        }
        return true;
    }

    public function toString():String {
        return this.map(token -> token.text).join(" -> ");
    }
}

class PositionAwareWalker extends StackAwareWalker {
    var line:Int = 0;
    var character:Int = 0;

    var scope = new Scope();

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

    override function walkEnumDecl(node:EnumDecl, stack:WalkStack) {
        scope.push(node.name);
        super.walkEnumDecl(node, stack);
        scope.pop();
    }

    override function walkAbstractDecl(node:AbstractDecl, stack:WalkStack) {
        scope.push(node.name);
        super.walkAbstractDecl(node, stack);
        scope.pop();
    }

    override function walkClassDecl(node:ClassDecl, stack:WalkStack) {
        scope.push(node.name);
        super.walkClassDecl(node, stack);
        scope.pop();
    }

    override function walkTypedefDecl(node:TypedefDecl, stack:WalkStack) {
        scope.push(node.name);
        super.walkTypedefDecl(node, stack);
        scope.pop();
    }

    override function walkFunction(node:Function, stack:WalkStack) {
        scope.push(node.name);
        super.walkFunction(node, stack);
        scope.pop();
    }

    override function walkClassField_Function(annotations:NAnnotations, modifiers:Array<FieldModifier>, functionKeyword:Token, name:Token, params:Null<TypeDeclParameters>, parenOpen:Token, args:Null<CommaSeparated<FunctionArgument>>, parenClose:Token, typeHint:Null<TypeHint>, expr:MethodExpr, stack:WalkStack) {
        scope.push(name);
        super.walkClassField_Function(annotations, modifiers, functionKeyword, name, params, parenOpen, args, parenClose, typeHint, expr, stack);
        scope.pop();
    }

    override function walkExpr_EBlock(braceOpen:Token, elems:Array<BlockElement>, braceClose:Token, stack:WalkStack) {
        scope.push(braceOpen);
        super.walkExpr_EBlock(braceOpen, elems, braceClose, stack);
        scope.pop();
    }
}
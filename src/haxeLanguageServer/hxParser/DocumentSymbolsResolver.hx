package haxeLanguageServer.hxParser;

import hxParser.ParseTree;
import hxParser.StackAwareWalker;
import hxParser.WalkStack;
using Lambda;

class DocumentSymbolsResolver extends StackAwareWalker {
    var uri:DocumentUri;
    var line:Int = 0;
    var character:Int = 0;
    var tokenMap:Map<Token, SymbolKind> = new Map();

    public var results(default, null):Array<SymbolInformation> = [];

    public function new(uri:DocumentUri) {
        this.uri = uri;
    }

    override function walkToken(token:Token, stack:WalkStack) {
        updatePosition(token.leadingTrivia);

        if (tokenMap[token] != null) {
            results.push({
                name: token.text,
                kind: tokenMap[token],
                location: {
                    uri: uri,
                    range: {
                        start: {line: line, character: character},
                        end: {line: line, character: character + token.text.length}
                    }
                }
            });
            tokenMap[token] = null;
        }

        character += token.text.length;
        updatePosition(token.trailingTrivia);
    }

    function updatePosition(trivias:Array<Trivia>) {
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

    override function walkTypedefDecl(node:TypedefDecl, stack:WalkStack) {
        tokenMap[node.name] = SymbolKind.Interface;
        super.walkTypedefDecl(node, stack);
    }

    override function walkClassDecl(node:ClassDecl, stack:WalkStack) {
        tokenMap[node.name] = if (node.kind.text == "interface") SymbolKind.Interface else SymbolKind.Class;
        super.walkClassDecl(node, stack);
    }

    override function walkEnumDecl(node:EnumDecl, stack:WalkStack) {
        tokenMap[node.name] = SymbolKind.Enum;
        super.walkEnumDecl(node, stack);
    }

    override function walkAbstractDecl(node:AbstractDecl, stack:WalkStack) {
        tokenMap[node.name] = SymbolKind.Class;
        super.walkAbstractDecl(node, stack);
    }

    override function walkClassField_Function(annotations:NAnnotations, modifiers:Array<FieldModifier>, functionKeyword:Token, name:Token, params:Null<TypeDeclParameters>, parenOpen:Token, args:Null<CommaSeparated<FunctionArgument>>, parenClose:Token, typeHint:Null<TypeHint>, expr:MethodExpr, stack:WalkStack) {
        tokenMap[name] = if (name.text == "new") SymbolKind.Constructor else SymbolKind.Function;
        super.walkClassField_Function(annotations, modifiers, functionKeyword, name, params, parenOpen, args, parenClose, typeHint, expr, stack);
    }

    override function walkFunctionArgument(node:FunctionArgument, stack:WalkStack) {
        tokenMap[node.name] = SymbolKind.Variable;
        super.walkFunctionArgument(node, stack);
    }

    override function walkClassField_Variable(annotations:NAnnotations, modifiers:Array<FieldModifier>, varKeyword:Token, name:Token, typeHint:Null<TypeHint>, assignment:Null<Assignment>, semicolon:Token, stack:WalkStack) {
        var isInline = modifiers.exists(function(modifier) return modifier.match(FieldModifier.Inline(_)));
        tokenMap[name] = if (isInline) SymbolKind.Constant else SymbolKind.Field;
        super.walkClassField_Variable(annotations, modifiers, varKeyword, name, typeHint, assignment, semicolon, stack);
    }

    override function walkClassField_Property(annotations:NAnnotations, modifiers:Array<FieldModifier>, varKeyword:Token, name:Token, parenOpen:Token, read:Token, comma:Token, write:Token, parenClose:Token, typeHint:Null<TypeHint>, assignment:Null<Assignment>, semicolon:Token, stack:WalkStack) {
        tokenMap[name] = SymbolKind.Property;
        super.walkClassField_Property(annotations, modifiers, varKeyword, name, parenOpen, read, comma, write, parenClose, typeHint, assignment, semicolon, stack);
    }

    override function walkVarDecl(node:VarDecl, stack:WalkStack) {
        tokenMap[node.name] = SymbolKind.Variable;
        super.walkVarDecl(node, stack);
    }

    override function walkBlockElement_InlineFunction(inlineKeyword:Token, functionKeyword:Token, fun:Function, semicolon:Token, stack:WalkStack) {
        if (fun.name != null) tokenMap[fun.name] = SymbolKind.Function;
        super.walkBlockElement_InlineFunction(inlineKeyword, functionKeyword, fun, semicolon, stack);
    }

    override function walkExpr_EVar(varKeyword:Token, decl:VarDecl, stack:WalkStack) {
        tokenMap[decl.name] = SymbolKind.Variable;
        super.walkExpr_EVar(varKeyword, decl, stack);
    }

    override function walkExpr_EFunction(functionKeyword:Token, fun:Function, stack:WalkStack) {
        if (fun.name != null) tokenMap[fun.name] = SymbolKind.Function;
        super.walkExpr_EFunction(functionKeyword, fun, stack);
    }
}
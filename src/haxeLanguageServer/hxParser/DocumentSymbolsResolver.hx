package haxeLanguageServer.hxParser;

import hxParser.ParseTree;
import hxParser.WalkStack;
import haxeLanguageServer.hxParser.Helper;

class DocumentSymbolsResolver extends PositionAwareWalker {
    final uri:DocumentUri;
    final symbols:Map<Token, SymbolInformation> = new Map();

    public function new(uri:DocumentUri) {
        this.uri = uri;
    }

    public function getSymbols():Array<SymbolInformation> {
        return [for (symbol in symbols) if (symbol.location != null) symbol];
    }

    override function processToken(token:Token, stack:WalkStack) {
        if (symbols[token] != null) {
            symbols[token].location = {
                uri: uri,
                range: {
                    start: {line: line, character: character},
                    end: {line: line, character: character + token.text.length}
                }
            };
        }

        super.processToken(token, stack);
    }

    function getScope(stack:WalkStack):String {
        var segments = [];
        function loop(stack:WalkStack) {
            switch (stack) {
                case Edge(edge, parent):
                    loop(parent);
                case Element(index, parent):
                    loop(parent);
                case Node(kind, parent):
                    function add(name:Token) {
                        if (name != null) {
                            segments.unshift(name.text);
                        }
                    }
                    switch (kind) {
                        case AbstractDecl(decl): add(decl.name);
                        case ClassDecl(decl): add(decl.name);
                        case EnumDecl(decl): add(decl.name);
                        case TypedefDecl(decl): add(decl.name);
                        case Function(node): add(node.name);
                        case ClassField_Function(_, _, _, name, _, _, _, _, _, _):
                            add(name);
                        case _:
                    };
                    loop(parent);
                case Root:
            };
        }
        loop(stack);
        return segments.join(".");
    }

    function addSymbol(token:Token, kind:SymbolKind, stack:WalkStack) {
        symbols[token] = {
            name: token.text,
            kind: kind,
            location: null,
            containerName: getScope(stack)
        };
    }

    override function walkTypedefDecl(node:TypedefDecl, stack:WalkStack) {
        var kind = switch (node.type) {
            case AnonymousStructure(_, _, _): SymbolKind.Struct;
            case StructuralExtension(_, _, _): SymbolKind.Struct;
            case _: SymbolKind.Interface;
        }
        addSymbol(node.name, kind, stack);
        super.walkTypedefDecl(node, stack);
    }

    override function walkClassDecl(node:ClassDecl, stack:WalkStack) {
        var kind = if (node.kind.text == "interface") SymbolKind.Interface else SymbolKind.Class;
        addSymbol(node.name, kind, stack);
        super.walkClassDecl(node, stack);
    }

    override function walkEnumDecl(node:EnumDecl, stack:WalkStack) {
        addSymbol(node.name, SymbolKind.Enum, stack);
        super.walkEnumDecl(node, stack);
    }

    override function walkAbstractDecl(node:AbstractDecl, stack:WalkStack) {
        var kind = if (Helper.isInAbstractEnum(stack)) SymbolKind.Enum else SymbolKind.Class;
        addSymbol(node.name, kind, stack);
        super.walkAbstractDecl(node, stack);
    }

    override function walkClassField_Function(annotations:NAnnotations, modifiers:Array<FieldModifier>, functionKeyword:Token, name:Token, params:Null<TypeDeclParameters>, parenOpen:Token, args:Null<CommaSeparated<FunctionArgument>>, parenClose:Token, typeHint:Null<TypeHint>, expr:MethodExpr, stack:WalkStack) {
        var kind =
            if (Helper.isOperator(stack, annotations.metadata)) SymbolKind.Operator
            else if (name.text == "new") SymbolKind.Constructor
            else SymbolKind.Function;

        addSymbol(name, kind, stack);
        super.walkClassField_Function(annotations, modifiers, functionKeyword, name, params, parenOpen, args, parenClose, typeHint, expr, stack);
    }

    override function walkFunctionArgument(node:FunctionArgument, stack:WalkStack) {
        addSymbol(node.name, SymbolKind.Variable, stack);
        super.walkFunctionArgument(node, stack);
    }

    override function walkClassField_Variable(annotations:NAnnotations, modifiers:Array<FieldModifier>, varKeyword:Token, name:Token, typeHint:Null<TypeHint>, assignment:Null<Assignment>, semicolon:Token, stack:WalkStack) {
        var kind =
            if (Helper.isAbstractEnumValue(stack, modifiers)) SymbolKind.EnumMember
            else if (Helper.isInline(modifiers)) SymbolKind.Constant
            else SymbolKind.Field;

        addSymbol(name, kind, stack);
        super.walkClassField_Variable(annotations, modifiers, varKeyword, name, typeHint, assignment, semicolon, stack);
    }

    override function walkClassField_Property(annotations:NAnnotations, modifiers:Array<FieldModifier>, varKeyword:Token, name:Token, parenOpen:Token, read:Token, comma:Token, write:Token, parenClose:Token, typeHint:Null<TypeHint>, assignment:Null<Assignment>, semicolon:Token, stack:WalkStack) {
        addSymbol(name, SymbolKind.Property, stack);
        super.walkClassField_Property(annotations, modifiers, varKeyword, name, parenOpen, read, comma, write, parenClose, typeHint, assignment, semicolon, stack);
    }

    override function walkVarDecl(node:VarDecl, stack:WalkStack) {
        addSymbol(node.name, SymbolKind.Variable, stack);
        super.walkVarDecl(node, stack);
    }

    override function walkFunction(node:Function, stack:WalkStack) {
        if (node.name != null) addSymbol(node.name, SymbolKind.Function, stack);
        super.walkFunction(node, stack);
    }

    override function walkExpr_EVar(varKeyword:Token, decl:VarDecl, stack:WalkStack) {
        addSymbol(decl.name, SymbolKind.Variable, stack);
        super.walkExpr_EVar(varKeyword, decl, stack);
    }

    override function walkNEnumField(node:NEnumField, stack:WalkStack) {
        addSymbol(node.name, SymbolKind.EnumMember, stack);
        super.walkNEnumField(node, stack);
    }

    override function walkAnonymousStructureField(node:AnonymousStructureField, stack:WalkStack) {
        addSymbol(node.name, SymbolKind.Variable, stack);
        super.walkAnonymousStructureField(node, stack);
    }

    override function walkExpr_EIn(exprLeft:Expr, inKeyword:Token, exprRight:Expr, stack:WalkStack) {
        switch (exprLeft) {
            case EConst(PConstIdent(variable)):
                addSymbol(variable, SymbolKind.Variable, stack);
            case _:
        }
        super.walkExpr_EIn(exprLeft, inKeyword, exprRight, stack);
    }

    override function walkCatch(node:Catch, stack:WalkStack) {
        addSymbol(node.ident, SymbolKind.Variable, stack);
        super.walkCatch(node, stack);
    }

    override function walkTypeDeclParameter(node:TypeDeclParameter, stack:WalkStack) {
        addSymbol(node.name, SymbolKind.TypeParameter, stack);
        super.walkTypeDeclParameter(node, stack);
    }
}
package haxeLanguageServer.hxParser;

import haxeLanguageServer.hxParser.PositionAwareWalker.Scope;
import hxParser.ParseTree;
import hxParser.WalkStack;

using Lambda;
using hxParser.WalkStackTools;

private typedef DeclInfo = {
	var scope:Scope;
	var isCaptureVariable:Bool;
}

class RenameResolver extends PositionAwareWalker {
	public final edits:Array<TextEdit> = [];

	final declaration:Range;
	final newName:String;
	final rangeConsumers = new Map<Token, Range->Void>();
	var declarationInfo:DeclInfo;
	var declarationInScope = false;
	var declarationIdentifier:String;
	var inStaticFunction:Bool = false;
	var typeName:String;
	final shadowingDecls:Array<DeclInfo> = [];
	final newIdentShadowingDecls:Array<DeclInfo> = [];

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
		if (!declarationInScope) {
			var range = getRange();
			if (declaration.isEqual(range)) {
				declarationInScope = true;
				declarationInfo = {
					scope: scope.copy(),
					isCaptureVariable: isCaptureVariable(stack)
				};
				declarationIdentifier = getRawIdentifier(token.text);

				range.start = range.start.translate(0, getIdentifierOffset(token.text));
				edits.push({
					range: range,
					newText: newName
				});
			}
		}

		var consumer = rangeConsumers[token];
		if (consumer != null) {
			consumer(getRange());
			rangeConsumers.remove(token);
		}

		super.processToken(token, stack);
	}

	function checkShadowing(token:Token, stack:WalkStack, isCaptureVariable:Bool = false) {
		if (!isCaptureVariable && handleDollarIdent(token, stack)) {
			// in this case it's a usage and can't shadow (unless it's a capture var)
			return;
		}

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

		if (declarationIdentifier == getRawIdentifier(token.text)) {
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
		handleIdent(ident, stack);
		super.walkNConst_PConstIdent(ident, stack);
	}

	override function walkExpr_EDollarIdent(ident:Token, stack:WalkStack) {
		checkShadowing(ident, stack, isMacroCaptureVariable(stack));
		super.walkExpr_EDollarIdent(ident, stack);
	}

	override function walkNDotIdent_PDotIdent(name:Token, stack:WalkStack) {
		if (name.text.startsWith(".$")) {
			handleIdent(name, stack);
		}
		super.walkNDotIdent_PDotIdent(name, stack);
	}

	override function walkObjectFieldName_NIdent(ident:Token, stack:WalkStack) {
		handleDollarIdent(ident, stack);
		super.walkObjectFieldName_NIdent(ident, stack);
	}

	override function walkFunction(node:Function, stack:WalkStack) {
		if (node.name != null) {
			handleDollarIdent(node.name, stack);
		}
		super.walkFunction(node, stack);
	}

	function isCaptureVariable(stack:WalkStack):Bool {
		return stack.find(stack -> stack.match(Edge("patterns", Node(Case_Case(_, _, _, _, _), _)))) != null;
	}

	function isMacroCaptureVariable(stack:WalkStack):Bool {
		var macroStack = stack.find(stack -> stack.match(Node(Expr_EMacro(_, _), _)));
		if (macroStack != null) {
			return isCaptureVariable(macroStack);
		}
		return false;
	}

	function isCaptureVariableInSameScope(decl:DeclInfo, scope:Scope) {
		return decl.isCaptureVariable && decl.scope.equals(scope);
	}

	function handleIdent(ident:Token, stack:WalkStack) {
		var identText = getRawIdentifier(ident.text);
		// assume that lowercase idents in `case` are capture vars
		var firstChar = identText.charAt(0);
		if (ident.text.charAt(0) != "$"
			&& firstChar == firstChar.toLowerCase()
			&& isCaptureVariable(stack)
			&& (declarationInfo == null || !isCaptureVariableInSameScope(declarationInfo, scope))) {
			checkShadowing(ident, stack, true);
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

	function getIdentifierOffset(ident:String):Int {
		return if (ident.startsWith("$")) {
			1;
		} else if (ident.startsWith(".$")) {
			2;
		} else {
			0;
		}
	}

	inline function getRawIdentifier(ident:String) {
		return ident.substr(getIdentifierOffset(ident));
	}

	function handleDollarIdent(ident:Token, stack:WalkStack):Bool {
		if (ident.text.startsWith("$")) {
			handleIdent(ident, stack);
			return true;
		}
		return false;
	}

	override function walkVarDecl(node:VarDecl, stack:WalkStack) {
		checkShadowing(node.name, stack);
		super.walkVarDecl(node, stack);
	}

	override function walkFunctionArgument(node:FunctionArgument, stack:WalkStack) {
		checkShadowing(node.name, stack);
		super.walkFunctionArgument(node, stack);
	}

	override function walkExpr_EIn(exprLeft:Expr, inKeyword:Token, exprRight:Expr, stack:WalkStack) {
		switch (exprLeft) {
			case EConst(PConstIdent(variable)):
				checkShadowing(variable, stack);
			case _:
		}
		super.walkExpr_EIn(exprLeft, inKeyword, exprRight, stack);
	}

	override function walkCatch(node:Catch, stack:WalkStack) {
		scope.push(node.catchKeyword);
		checkShadowing(node.ident, stack);
		super.walkCatch(node, stack);
		closeScope();
	}

	override function walkClassField_Function(annotations:NAnnotations, modifiers:Array<FieldModifier>, functionKeyword:Token, name:Token,
			params:Null<TypeDeclParameters>, parenOpen:Token, args:Null<CommaSeparated<FunctionArgument>>, parenClose:Token, typeHint:Null<TypeHint>,
			expr:MethodExpr, stack:WalkStack) {
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

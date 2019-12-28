package haxeLanguageServer.features.documentSymbols;

import haxeLanguageServer.features.documentSymbols.SymbolStack;
import tokentree.TokenTree;

using tokentree.TokenTreeAccessHelper;
using tokentree.utils.FieldUtils;
using tokentree.utils.TokenTreeCheckUtils;

class DocumentSymbolsResolver {
	final document:TextDocument;

	public function new(document:TextDocument) {
		this.document = document;
	}

	public function resolve():Array<DocumentSymbol> {
		var stack = new SymbolStack();
		var tokens = document.tokens;
		if (tokens == null) {
			return [];
		}
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
				if (level == Expression && name == "_") {
					return; // naming vars "_" is a common convention for ignoring them
				}
				if (opensScope == null) {
					opensScope = true;
				}
				var range = tokens.getTreePos(token);
				if (level != Expression) {
					var docComment = token.getDocComment();
					if (docComment != null) {
						var docCommentPos = tokens.getPos(docComment);
						range = {file: range.file, min: docCommentPos.min, max: range.max};
					}
				}
				var symbol:DocumentSymbol = {
					name: name,
					kind: kind,
					range: rangeAt(range),
					selectionRange: rangeAt(tokens.getPos(nameToken))
				};
				if (token.isDeprecated()) {
					symbol.deprecated = true;
				}
				stack.addSymbol(level, symbol, opensScope);
			}

			switch token.tok {
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
					var currentLevel = switch stack.level {
						case Root, Type(_): Field;
						case Field, Expression: Expression;
					};
					switch token.getFieldType(PRIVATE) {
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
					switch stack.getParentTypeKind() {
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
		return stack.root.children;
	}

	inline function rangeAt(pos:haxe.macro.Expr.Position):Range {
		return document.rangeAt(pos.min, pos.max);
	}
}

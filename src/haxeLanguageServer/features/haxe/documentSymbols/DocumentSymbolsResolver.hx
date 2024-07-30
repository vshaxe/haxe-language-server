package haxeLanguageServer.features.haxe.documentSymbols;

import haxeLanguageServer.features.haxe.documentSymbols.SymbolStack;
import languageServerProtocol.Types.DocumentSymbol;
import languageServerProtocol.Types.SymbolKind;
import tokentree.TokenTree;

using tokentree.TokenTreeAccessHelper;
using tokentree.utils.FieldUtils;
using tokentree.utils.TokenTreeCheckUtils;

class DocumentSymbolsResolver {
	final document:HaxeDocument;

	public function new(document:HaxeDocument) {
		this.document = document;
	}

	public function resolve():Null<Array<DocumentSymbol>> {
		final stack = new SymbolStack();
		final tokens = document.tokens;
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
					if (name == null) {
						return;
					}
				}
				if (level == Expression && name == "_") {
					return; // naming vars "_" is a common convention for ignoring them
				}
				if (opensScope == null) {
					opensScope = true;
				}
				var range = tokens.getTreePos(token);
				if (level != Expression) {
					final docComment = token.getDocComment();
					if (docComment != null) {
						final docCommentPos = tokens.getPos(docComment);
						range = {file: range.file, min: docCommentPos.min, max: range.max};
					}
				}
				@:nullSafety(Off)
				final symbol:DocumentSymbol = {
					name: name,
					kind: kind,
					range: rangeAt(range),
					selectionRange: rangeAt(tokens.getPos(nameToken))
				};
				if (token.isDeprecated()) {
					symbol.tags = [Deprecated];
				}
				stack.addSymbol(level, symbol, opensScope);
			}

			switch token.tok {
				case Kwd(KwdClass):
					var name = token.getNameToken()?.getName();
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
					final currentLevel:SymbolLevel = switch stack.level {
						case Root, Type(_): Field;
						case Field, Expression: Expression;
					};
					switch token.getFieldType(Private) {
						case Function(name, _, _, _, _, _, _):
							if (name == null) {
								name = "<anonymous function>";
							}
							final type = stack.getParentTypeKind();
							final kind:SymbolKind = if (name == "new") {
								Constructor;
							} else if (token.isOperatorFunction() && (type == Abstract || type == EnumAbstract)) {
								Operator;
							} else {
								Method;
							}
							add(token, kind, currentLevel, name);

						case Var(name, _, isStatic, isInline, _, _):
							if (currentLevel == Expression) {
								final children = token.children;
								if (children != null) {
									// at expression level, we might have a multi-final expr (`final a, b, c;`)
									for (i in 0...children.length) {
										final opensScope = i == children.length - 1;
										final token = if (i == 0) token else children[i];
										add(token, Variable, currentLevel, opensScope);
									}
								}
							} else {
								final type = stack.getParentTypeKind();
								final kind:SymbolKind = if (type == EnumAbstract && !isStatic) {
									EnumMember;
								} else if (isInline) {
									Constant;
								} else {
									Field;
								}
								add(token, kind, currentLevel, name);
							}

						case Prop(name, _, _, _, _):
							add(token, Property, currentLevel, name);

						case Unknown:
					}

				case Kwd(KwdFor), Kwd(KwdCatch):
					final ident:Null<TokenTree> = token.access().firstChild().matches(POpen).firstChild().isCIdent().token;
					if (ident != null) {
						add(ident, Variable, Expression, false);
					}

				case Const(CIdent(_)):
					switch stack.getParentTypeKind() {
						case null:
						case Enum:
							if (token.access().parent().matches(BrOpen).exists()) {
								add(token, EnumMember, Field);
							}
						case Struct:
							var parent = token.access().parent();
							if (parent.matches(Question).exists()) {
								parent = parent.parent();
							}
							if (parent.matches(BrOpen).exists()) {
								add(token, Field, Field);
							}
						case _:
					}

				case _:
			}
			return GoDeeper;
		});
		return stack.root.children;
	}

	inline function rangeAt(pos:haxe.macro.Expr.Position):Range {
		return document.rangeAt(pos.min, pos.max);
	}
}

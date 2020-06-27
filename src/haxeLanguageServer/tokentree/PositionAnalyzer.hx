package haxeLanguageServer.tokentree;

import haxeLanguageServer.tokentree.TokenContext;
import haxeparser.Data.TokenDef;
import tokentree.TokenTree;
import tokentree.utils.TokenTreeCheckUtils;

using tokentree.TokenTreeAccessHelper;

class PositionAnalyzer {
	final document:HaxeDocument;

	public function new(document:HaxeDocument) {
		this.document = document;
	}

	public function resolve(pos:Position):Null<TokenTree> {
		final tokens = document.tokens;
		if (tokens == null) {
			return null;
		}
		var found = false;
		var result:Null<TokenTree> = null;
		tokens.tree.filterCallback(function(token:TokenTree, _) {
			if (found) {
				return SKIP_SUBTREE;
			}
			final tokenPos = document.rangeAt2(tokens.getPos(token));
			if (tokenPos.containsPos(pos)) {
				result = token;
				found = true;
				return SKIP_SUBTREE;
			}
			final tokenTreePos = document.rangeAt2(tokens.getTreePos(token));
			if (tokenTreePos.containsPos(pos)) {
				result = token;
				return GO_DEEPER;
			}
			return SKIP_SUBTREE;
		});
		return result;
	}

	public static function getStringKind(token:Null<TokenTree>, document:HaxeDocument, pos:Position):StringKind {
		final tokens = document.tokens;
		if (token == null || tokens == null) {
			return None;
		}
		return switch token.tok {
			case Const(CString(_)):
				final startPos = document.positionAt(tokens.getPos(token).min);
				return switch document.characterAt(startPos) {
					case "'": SingleQuote;
					case '"': DoubleQuote;
					case _: None;
				}
			case _:
				None;
		}
	}

	public static function getContext(token:Null<TokenTree>, document:HaxeDocument, completionPosition:Position):TokenContext {
		final tokens = document.tokens;
		if (token == null || tokens == null) {
			return Root(BeforePackage);
		}
		inline function isType(tok:TokenDef) {
			return tok.match(Kwd(KwdClass | KwdInterface | KwdAbstract | KwdEnum | KwdTypedef));
		}
		var typeToken = null;
		var fieldToken = null;
		var hasBlockParent = false;

		var parent = token.access();
		while (parent.exists() && parent.token != null && parent.token.tok != null) {
			switch parent.token.tok {
				case BrOpen if (TokenTreeCheckUtils.getBrOpenType(parent.token) == BLOCK):
					hasBlockParent = true;
				case tok if (isType(tok) && hasBlockParent):
					typeToken = parent.token;
					break;
				case Kwd(KwdFunction | KwdVar | KwdFinal) if (!TokenTreeCheckUtils.isModifier(token)):
					fieldToken = parent.token;
				case _:
			}
			parent = parent.parent();
		}

		function getFieldKind():FieldKind {
			return switch fieldToken!.tok {
				case Kwd(KwdVar): Var;
				case Kwd(KwdFinal): Final;
				case Kwd(KwdFunction): Function;
				case _: throw "assert false";
			}
		}

		if (typeToken != null) {
			return Type({
				kind: if (typeToken != null) {
					switch typeToken.tok {
						case Kwd(KwdClass): if (TokenTreeCheckUtils.isTypeMacroClass(typeToken)) MacroClass else Class;
						case Kwd(KwdInterface): Interface;
						case Kwd(KwdAbstract): if (TokenTreeCheckUtils.isTypeEnumAbstract(typeToken)) EnumAbstract else Abstract;
						case Kwd(KwdEnum): if (TokenTreeCheckUtils.isTypeEnumAbstract(typeToken)) EnumAbstract else Enum;
						case Kwd(KwdTypedef): Typedef;
						case _: null;
					}
				} else {
					null;
				},
				field: if (fieldToken != null) {
					isStatic: fieldToken.access().child(0).firstOf(Kwd(KwdStatic)).exists(),
					kind: getFieldKind()
				} else {
					null;
				}
			});
		}

		if (typeToken == null && fieldToken != null) {
			return ModuleLevelStatic(getFieldKind());
		}

		var pos = BeforePackage;
		final root = tokens.tree;
		if (root.children == null) {
			return Root(pos);
		}
		for (child in root.children) {
			final childPos = document.rangeAt2(tokens.getPos(child));
			if (childPos.start.isAfter(completionPosition)) {
				break;
			}
			switch child.tok {
				case Kwd(KwdPackage):
					pos = BeforeFirstImport;
				case Kwd(KwdImport | KwdUsing):
					pos = BeforeFirstType;
				case tok if (isType(tok)):
					pos = AfterFirstType;
				case _:
			}
		}
		return Root(pos);
	}
}

enum StringKind {
	None;
	SingleQuote;
	DoubleQuote;
}

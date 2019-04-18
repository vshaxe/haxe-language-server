package haxeLanguageServer.tokentree;

import haxeparser.Data.TokenDef;
import haxeLanguageServer.tokentree.TokenContext;
import tokentree.utils.TokenTreeCheckUtils;
import tokentree.TokenTree;

using tokentree.TokenTreeAccessHelper;

class PositionAnalyzer {
	final document:TextDocument;

	public function new(document:TextDocument) {
		this.document = document;
	}

	public function resolve(pos:Position):Null<TokenTree> {
		var tokens = document.tokens;
		if (tokens == null) {
			return null;
		}
		var found = false;
		var result:Null<TokenTree> = null;
		tokens.tree.filterCallback(function(token:TokenTree, _) {
			if (found) {
				return SKIP_SUBTREE;
			}
			var tokenPos = document.rangeAt2(tokens.getPos(token));
			if (tokenPos.containsPos(pos)) {
				result = token;
				found = true;
				return SKIP_SUBTREE;
			}
			var tokenTreePos = document.rangeAt2(tokens.getTreePos(token));
			if (tokenTreePos.containsPos(pos)) {
				result = token;
				return GO_DEEPER;
			}
			return SKIP_SUBTREE;
		});
		return result;
	}

	public static function getStringKind(token:Null<TokenTree>, document:TextDocument, pos:Position):StringKind {
		if (token == null) {
			return None;
		}
		return switch (token.tok) {
			case Const(CString(_)):
				var startPos = document.positionAt(document.tokens.getPos(token).min);
				return switch (document.characterAt(startPos)) {
					case "'": SingleQuote;
					case '"': DoubleQuote;
					case _: None;
				}
			case _:
				None;
		}
	}

	public static function getContext(token:Null<TokenTree>, document:TextDocument, completionPosition:Position):TokenContext {
		inline function isType(tok:TokenDef) {
			return tok.match(Kwd(KwdClass | KwdInterface | KwdAbstract | KwdEnum | KwdTypedef));
		}
		var typeToken = null;
		var fieldToken = null;

		var parent = token.access();
		while (parent.exists() && parent.token.tok != null) {
			switch (parent.token.tok) {
				case tok if (isType(tok) && typeToken == null):
					typeToken = parent.token;
				case Kwd(KwdFunction | KwdVar | KwdFinal):
					fieldToken = parent.token;
				case _:
			}
			parent = parent.parent();
		}

		if (typeToken != null) {
			return Type({
				kind: if (typeToken != null) {
					switch (typeToken.tok) {
						case Kwd(KwdClass): if (TokenTreeCheckUtils.isTypeMacroClass(typeToken)) MacroClass else Class;
						case Kwd(KwdInterface): Interface;
						case Kwd(KwdAbstract): Abstract;
						case Kwd(KwdEnum): if (TokenTreeCheckUtils.isTypeEnumAbstract(typeToken)) EnumAbstract else Enum;
						case Kwd(KwdTypedef): Typedef;
						case _: null;
					}
				} else {
					null;
				},
				field: if (fieldToken != null) {
					{
						isStatic: fieldToken.access().child(0).firstOf(Kwd(KwdStatic)).exists(),
						kind: switch (fieldToken.tok) {
							case Kwd(KwdVar): Var;
							case Kwd(KwdFinal): Final;
							case Kwd(KwdFunction): Function;
							case _: null;
						}
					}
				} else {
					null;
				}
			});
		}

		var pos = BeforePackage;
		var root = document.tokens.tree;
		if (root.children == null) {
			return Root(pos);
		}
		for (child in root.children) {
			var childPos = document.rangeAt2(document.tokens.getPos(child));
			if (childPos.start.isAfter(completionPosition)) {
				break;
			}
			switch (child.tok) {
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

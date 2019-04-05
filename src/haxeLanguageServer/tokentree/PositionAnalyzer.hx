package haxeLanguageServer.tokentree;

import tokentree.TokenTree;

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
		var result:Null<TokenTree> = null;
		tokens.tree.filterCallback(function(token:TokenTree, _) {
			if (result != null) {
				return SKIP_SUBTREE;
			}
			var tokenPos = document.rangeAt2(tokens.getPos(token));
			var tokenTreePos = document.rangeAt2(tokens.getTreePos(token));
			if (tokenPos.containsPos(pos)) {
				result = token;
				return SKIP_SUBTREE;
			}
			if (tokenTreePos.containsPos(pos)) {
				return GO_DEEPER;
			}
			return SKIP_SUBTREE;
		});
		return result;
	}

	public function getStringKind(pos:Position):StringKind {
		var token = resolve(pos);
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
}

enum StringKind {
	None;
	SingleQuote;
	DoubleQuote;
}
package haxeLanguageServer.features.haxe.codeAction;

import tokentree.TokenTree;

class TokenTreeUtils {
	public static function isInFunctionScope(token:TokenTree):Bool {
		final brOpen = token.parent ?? return false;
		if (brOpen.tok != BrOpen)
			return false;
		final name = brOpen.parent ?? return false;
		// `function() {}` or `() -> {}`
		if (name.tok.match(Kwd(KwdFunction) | Arrow))
			return true;
		final fun = name.parent ?? return false;
		// `function name() {}`
		return fun.tok.match(Kwd(KwdFunction));
	}

	public static function isFunctionArg(token:TokenTree):Bool {
		final pOpen = token.parent ?? return false;
		if (pOpen.tok != POpen)
			return false;
		final name = pOpen.parent ?? return false;
		// `function() {}` or `() -> {}`
		if (name.tok.match(Kwd(KwdFunction) | Arrow))
			return true;
		final fun = name.parent ?? return false;
		// `function name() {}`
		return fun.tok.match(Kwd(KwdFunction));
	}

	public static function isInLoopScope(token:TokenTree):Bool {
		var kwd = token.parent ?? return false;
		if (kwd.tok == BrOpen)
			kwd = kwd.parent ?? return false;
		return kwd.tok.match(Kwd(KwdFor | KwdDo | KwdWhile));
	}

	public static function isAnonStructure(brToken:TokenTree):Bool {
		if (brToken.tok == BrClose)
			brToken = brToken.parent ?? return false;
		final first = brToken!.getFirstChild() ?? return false;
		final colon = first.getFirstChild() ?? return false;
		if (colon.tok.match(DblDot) && !colon.nextSibling!.tok.match(Semicolon)) {
			return true;
		}
		return false;
	}

	public static function isAnonStructureField(token:TokenTree):Bool {
		final parent = token.parent ?? return false;
		if (!isAnonStructure(parent))
			return false;
		final colon = token.getFirstChild() ?? return false;
		return colon.tok.match(DblDot);
	}
}

package haxeLanguageServer.features.haxe.codeAction;

import tokentree.TokenTree;
import tokentree.utils.TokenTreeCheckUtils;

class TokenTreeUtils {
	public static function isInFunctionScope(token:TokenTree):Bool {
		final token = token.parent ?? return false;
		return isFunctionBrOpen(token);
	}

	public static function isFunctionBrOpen(brOpen:TokenTree):Bool {
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

	public static function isCallPOpen(pOpen:TokenTree):Bool {
		if (pOpen.tok != POpen)
			return false;
		return TokenTreeCheckUtils.getPOpenType(pOpen) == Call;
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
		if (brToken.tok != BrOpen)
			return false;
		final first = brToken?.getFirstChild() ?? return false;
		final colon = first.getFirstChild() ?? return false;
		if (colon.tok.match(DblDot) && !colon.nextSibling?.tok.match(Semicolon)) {
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

	public static function isAnonFunction(kwdFunction:TokenTree):Bool {
		if (!kwdFunction.tok.match(Kwd(KwdFunction)))
			return false;
		// first child is POpen, no name between `function` and `(`
		final first = kwdFunction.getFirstChild() ?? return false;
		return first.tok == POpen;
	}

	/**
		If `brToken` (`BrOpen` or `BrClose`) is the body block of an arrow function or anon function.
		Returns root token of that function (`Arrow` or `Kwd(KwdFunction)`) or `null`.
	**/
	public static function getAnonFunctionFromBlock(brToken:TokenTree):Null<TokenTree> {
		var brOpen = brToken;
		if (brOpen.tok == BrClose)
			brOpen = brOpen.parent ?? return null;
		if (brOpen.tok != BrOpen)
			return null;
		final parent = brOpen.parent ?? return null;
		if (parent.tok == Arrow)
			return parent;
		// anon function: BrOpen.parent = POpen, POpen.parent = KwdFunction
		if (parent.tok == POpen) {
			final grand = parent.parent;
			if (grand != null && isAnonFunction(grand))
				return grand;
		}
		return null;
	}

	/**
		If `pOpen` is the argument list of an arrow or anon function.
		Returns root token of that function (`Arrow` or `Kwd(KwdFunction)`) or `null`.
	**/
	public static function getAnonFunctionFromPOpen(pOpen:TokenTree):Null<TokenTree> {
		if (pOpen.tok != POpen)
			return null;
		// arrow args: POpen has Arrow as a child (last sibling after PClose)
		final children = pOpen.children;
		if (children != null) {
			for (child in children) {
				if (child.tok == Arrow)
					return child;
			}
		}
		// anon function args: POpen.parent is KwdFunction, and POpen is the first child
		final parent = pOpen.parent;
		if (parent != null && isAnonFunction(parent) && parent.getFirstChild() == pOpen)
			return parent;
		return null;
	}
}

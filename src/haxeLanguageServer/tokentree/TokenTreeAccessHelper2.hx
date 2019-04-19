package haxeLanguageServer.tokentree;

import tokentree.TokenTreeAccessHelper;

// TODO: remove this again when switching to latest tokentree
class TokenTreeAccessHelper2 {
	public static function findParent(token:TokenTreeAccessHelper, predicate:TokenTreeAccessHelper->Bool):TokenTreeAccessHelper {
		var parent:TokenTreeAccessHelper = token.parent();
		while (parent.exists() && parent.token.tok != null) {
			if (predicate(parent)) {
				return parent;
			}
			parent = parent.parent();
		}
		return null;
	}
}

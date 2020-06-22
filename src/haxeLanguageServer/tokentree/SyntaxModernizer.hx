package haxeLanguageServer.tokentree;

import haxeLanguageServer.helper.WorkspaceEditHelper;
import haxeparser.Data.KeywordPrinter;
import tokentree.TokenTree;

using tokentree.TokenTreeAccessHelper;

class SyntaxModernizer {
	final document:HaxeDocument;

	public function new(document:HaxeDocument) {
		this.document = document;
	}

	public function resolve():Array<CodeAction> {
		final actions:Array<CodeAction> = [];
		final tokens = document.tokens;
		if (tokens == null) {
			return actions;
		}
		tokens.tree.filterCallback(function(token:TokenTree, _) {
			switch token.tok {
				case Kwd(kwd) if (kwd == KwdEnum || kwd == KwdExtern || kwd == KwdFinal):
					final dblDot:Null<TokenTree> = token.access().parent().is(DblDot).token;
					final at:Null<TokenTree> = dblDot.access().parent().is(At).token;
					if (dblDot != null && at != null) {
						final range = document.rangeAt(tokens.getPos(at).min, tokens.getPos(dblDot).max);
						final keyword = KeywordPrinter.toString(kwd);
						actions.push({
							title: 'Replace @:$keyword with $keyword',
							kind: RefactorRewrite,
							edit: WorkspaceEditHelper._create(document, [{range: range, newText: ""}])
						});
					}
				case _:
			}
			return GO_DEEPER;
		});
		return actions;
	}
}

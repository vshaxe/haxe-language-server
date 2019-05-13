package haxeLanguageServer.tokentree;

import haxeparser.Data.KeywordPrinter;
import haxeLanguageServer.helper.WorkspaceEditHelper;
import tokentree.TokenTree;

using tokentree.TokenTreeAccessHelper;

class SyntaxModernizer {
	final document:TextDocument;

	public function new(document:TextDocument) {
		this.document = document;
	}

	public function resolve():Array<CodeAction> {
		var actions:Array<CodeAction> = [];
		var tokens = document.tokens;
		if (tokens == null) {
			return actions;
		}
		tokens.tree.filterCallback(function(token:TokenTree, _) {
			switch token.tok {
				case Kwd(kwd) if (kwd == KwdEnum || kwd == KwdExtern || kwd == KwdFinal):
					var dblDot = token.access().parent().is(DblDot).token;
					var at = dblDot.access().parent().is(At).token;
					if (at != null) {
						var range = document.rangeAt(tokens.getPos(at).min, tokens.getPos(dblDot).max);
						var keyword = KeywordPrinter.toString(kwd);
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

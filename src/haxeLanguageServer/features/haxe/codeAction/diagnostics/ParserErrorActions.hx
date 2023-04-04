package haxeLanguageServer.features.haxe.codeAction.diagnostics;

import languageServerProtocol.Types.CodeActionKind;
import tokentree.TokenTree;

class ParserErrorActions {
	public static function createParserErrorActions(context:Context, params:CodeActionParams, diagnostic:Diagnostic):Array<CodeAction> {
		if ((params.context.only != null) && (!params.context.only.contains(QuickFix))) {
			return [];
		}
		final actions:Array<CodeAction> = [];
		final arg = context.diagnostics.getArguments(params.textDocument.uri, ParserError, diagnostic.range);
		if (arg == null) {
			return actions;
		}

		if (arg.contains("`final var` is not supported, use `final` instead")) {
			final document = context.documents.getHaxe(params.textDocument.uri);
			actions.push({
				title: "Change to final",
				kind: CodeActionKind.QuickFix + ".auto",
				edit: WorkspaceEditHelper.create(context, params, [{range: diagnostic.range, newText: "final"}]),
				diagnostics: [diagnostic],
				isPreferred: true
			});
		}

		if (arg.contains("Missing ;")) {
			final document = context.documents.getHaxe(params.textDocument.uri);
			var errRange:Null<Range> = getMissingSemicolonPos(document, diagnostic.range.start);
			if (errRange != null) {
				actions.push({
					title: "Add missing ;",
					kind: CodeActionKind.QuickFix + ".auto",
					edit: WorkspaceEditHelper.create(context, params, [{range: (errRange : Range), newText: ";"}]),
					diagnostics: [diagnostic],
					isPreferred: true
				});
			}
		}

		if (arg.contains("Expected , or ]")) {
			final document = context.documents.getHaxe(params.textDocument.uri);
			var errRange:Null<Range> = getMissingSemicolonPos(document, diagnostic.range.start);
			if (errRange != null) {
				actions.push({
					title: "Add missing ,",
					kind: CodeActionKind.QuickFix + ".auto",
					edit: WorkspaceEditHelper.create(context, params, [{range: (errRange : Range), newText: ","}]),
					diagnostics: [diagnostic],
					isPreferred: true
				});
			}
		}

		return actions;
	}

	static function getMissingSemicolonPos(document:HaxeDocument, errPos:Position):Null<Range> {
		final tokens = document.tokens;
		if (tokens == null)
			return null;
		final errToken = tokens!.getTokenAtOffset(document.offsetAt(errPos));
		if (errToken == null)
			return null;
		final prev = getPrevNonCommentSibling(errToken);
		// hard to scan #blocks for missing ; prev line
		if (prev == null || prev.tok.match(Sharp(_)))
			return null;
		final last = getLastNonCommentToken(prev);
		final pos = last!.getPos();
		if (pos == null)
			return null;
		return document.rangeAt(pos.max, pos.max);
	}

	static function getPrevNonCommentSibling(token:Null<TokenTree>):Null<TokenTree> {
		do {
			token = token!.previousSibling;
		} while (token!.isComment() == true);
		return token;
	}

	static function getLastNonCommentToken(token:TokenTree):Null<TokenTree> {
		var lastChild:Null<TokenTree> = token.getLastChild();
		while (lastChild != null) {
			var newLast:Null<TokenTree> = lastChild.getLastChild();
			if (newLast!.isComment() == true)
				newLast = getPrevNonCommentSibling(newLast);
			if (newLast == null) {
				return lastChild;
			}
			lastChild = newLast;
		}
		return null;
	}
}

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
			final errRange = getMissingSemicolonPos(document, diagnostic.range.start);
			if (errRange != null) {
				final errRange:Range = errRange;
				final hasSemicolon = document.characterAt(errRange.start.translate(0, -1)) == ";";
				if (!hasSemicolon) { // do not generate `;;`
					actions.push({
						title: "Add missing ;",
						kind: CodeActionKind.QuickFix + ".auto",
						edit: WorkspaceEditHelper.create(context, params, [{range: errRange, newText: ";"}]),
						diagnostics: [diagnostic],
						isPreferred: true
					});
				}
			}
		}

		if (arg.contains("Expected }")) {
			final document = context.documents.getHaxe(params.textDocument.uri);
			final token = document!.tokens!.getTokenAtOffset(document.offsetAt(diagnostic.range.end));
			final prevToken = getPrevNonCommentSibling(token);
			if (prevToken != null) {
				final prevToken = getLastNonCommentToken(prevToken);
				switch [prevToken!.tok, token!.tok] {
					case [Semicolon, Semicolon]:
						actions.push({
							title: "Remove reduntant ;",
							kind: CodeActionKind.QuickFix + ".auto",
							edit: WorkspaceEditHelper.create(context, params, [{range: diagnostic.range, newText: ""}]),
							diagnostics: [diagnostic],
							isPreferred: true
						});
					case _:
				}
			}
		}

		if (arg.contains("Expected , or ]")) {
			final document = context.documents.getHaxe(params.textDocument.uri);
			final errRange:Null<Range> = getMissingSemicolonPos(document, diagnostic.range.start);
			if (errRange != null) {
				final errRange:Range = errRange;
				final hasComma = document.characterAt(errRange.start.translate(0, -1)) == ",";
				if (!hasComma) { // do not generate `,,`
					actions.push({
						title: "Add missing ,",
						kind: CodeActionKind.QuickFix + ".auto",
						edit: WorkspaceEditHelper.create(context, params, [{range: errRange, newText: ","}]),
						diagnostics: [diagnostic],
						isPreferred: true
					});
				}
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
		final pos = last.getPos();
		return document.rangeAt(pos.max, pos.max);
	}

	static function getPrevNonCommentSibling(token:Null<TokenTree>):Null<TokenTree> {
		do {
			token = token!.previousSibling;
		} while (token!.isComment() == true);
		return token;
	}

	static function getLastNonCommentToken(token:TokenTree):TokenTree {
		var lastChild:TokenTree = token;
		while (true) {
			final newLast = getLastNonCommentChild(lastChild);
			if (newLast == null) {
				return lastChild;
			}
			lastChild = newLast;
		}
		return lastChild;
	}

	static function getLastNonCommentChild(token:TokenTree):Null<TokenTree> {
		final children = token.children;
		if (children == null)
			return null;
		var i = children.length;
		while (i-- > 0) {
			final child = children[i];
			if (child!.isComment() == false)
				return child;
		}
		return null;
	}
}

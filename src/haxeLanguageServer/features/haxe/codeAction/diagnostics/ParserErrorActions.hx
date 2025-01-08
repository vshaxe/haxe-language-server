package haxeLanguageServer.features.haxe.codeAction.diagnostics;

import languageServerProtocol.Types.CodeActionKind;
import tokentree.TokenTree;

class ParserErrorActions {
	public static function createParserErrorActions(context:Context, params:CodeActionParams, diagnostic:Diagnostic):Array<CodeAction> {
		if ((params.context.only != null) && (!params.context.only.contains(QuickFix))) {
			return [];
		}
		final actions:Array<CodeAction> = [];
		final arg = context.diagnostics.getArguments(params.textDocument.uri, DKParserError, diagnostic.range);
		if (arg == null) {
			return actions;
		}

		if (arg.contains("modifier is not supported for module-level fields") && diagnostic.range != null) {
			final document = context.documents.getHaxe(params.textDocument.uri);
			final nextText = document.content.substr(document.offsetAt(diagnostic.range.end));
			final isAuto = nextText.split("{").length == nextText.split("}").length;
			final token = document?.tokens?.getTokenAtOffset(document.offsetAt(diagnostic.range.end));
			var range = diagnostic.range.sure();
			if (token != null) {
				for (sib in [token.previousSibling, token.nextSibling]) {
					if (sib == null)
						continue;
					if (sib.tok.match(Kwd(KwdStatic)) || sib.tok.match(Kwd(KwdPublic))) {
						range = range.union(document.rangeAt(sib.pos.min, sib.pos.max, Utf8));
					}
				}
			}
			range.end = range.end.translate(0, 1);
			actions.push({
				title: "Remove redundant modifiers",
				kind: CodeActionKind.QuickFix + (isAuto ? ".auto" : ""),
				edit: WorkspaceEditHelper.create(context, params, [
					{
						range: range,
						newText: ""
					}
				]),
				diagnostics: [diagnostic],
				isPreferred: true
			});
		}

		if (arg.contains("`final var` is not supported, use `final` instead") && diagnostic.range != null) {
			final document = context.documents.getHaxe(params.textDocument.uri);
			actions.push({
				title: "Change to final",
				kind: CodeActionKind.QuickFix + ".auto",
				edit: WorkspaceEditHelper.create(context, params, [{range: diagnostic.range.sure(), newText: "final"}]),
				diagnostics: [diagnostic],
				isPreferred: true
			});
		}

		if (arg.contains("Missing ;")) {
			createMissingSemicolonAction(context, params, diagnostic, actions);
		}

		if (arg.contains("Expected }") && diagnostic.range != null) {
			final document = context.documents.getHaxe(params.textDocument.uri);
			final token = document?.tokens?.getTokenAtOffset(document.offsetAt(diagnostic.range.end));
			final prevToken = getPrevNonCommentSibling(token);
			if (prevToken != null && token != null) {
				final prevToken = getLastNonCommentToken(prevToken);
				switch [prevToken.tok, token.tok] {
					case [Semicolon, Semicolon]:
						actions.push({
							title: "Remove redundant ;",
							kind: CodeActionKind.QuickFix + ".auto",
							edit: WorkspaceEditHelper.create(context, params, [{range: diagnostic.range.sure(), newText: ""}]),
							diagnostics: [diagnostic],
							isPreferred: true
						});
					case [Comma, Comma]:
						actions.push({
							title: "Remove redundant ,",
							kind: CodeActionKind.QuickFix + ".auto",
							edit: WorkspaceEditHelper.create(context, params, [{range: diagnostic.range.sure(), newText: ""}]),
							diagnostics: [diagnostic],
							isPreferred: true
						});
					case [_, Semicolon]:
						// fix {b: value;} structure
						final colon = token.previousSibling ?? return actions;
						final field = colon.parent ?? return actions;
						final brOpen = field.parent ?? return actions;
						if (colon.tok == DblDot && field.tok.match(Const(_)) && brOpen.tok == BrOpen) {
							actions.push({
								title: "Replace ; with ,",
								kind: CodeActionKind.QuickFix + ".auto",
								edit: WorkspaceEditHelper.create(context, params, [{range: diagnostic.range.sure(), newText: ","}]),
								diagnostics: [diagnostic],
								isPreferred: true
							});
						}
					case [prevTok, _] if (!prevTok.match(Comma | BrOpen)):
						// fix {a: 0 b: 0} structure
						if (isAnonStructureField(token)) {
							final prevRange = document.rangeAt(prevToken.pos.max, prevToken.pos.max, Utf8);
							actions.push({
								title: "Add missing ,",
								kind: CodeActionKind.QuickFix + ".auto",
								edit: WorkspaceEditHelper.create(context, params, [{range: prevRange, newText: ","}]),
								diagnostics: [diagnostic],
								isPreferred: true
							});
						}
					case _:
				}
			}
		}

		if (arg.contains("Expected , or ]") && diagnostic.range != null) {
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

	static function createMissingSemicolonAction(context:Context, params:CodeActionParams, diagnostic:Diagnostic, actions:Array<CodeAction>):Void {
		final document = context.documents.getHaxe(params.textDocument.uri);
		final errRange = Safety.let(diagnostic.range, range -> getMissingSemicolonPos(document, range.start.translate(0, 1)));
		if (errRange == null)
			return;
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

	static function getMissingSemicolonPos(document:HaxeDocument, errPos:Position):Null<Range> {
		final tokens = document.tokens;
		if (tokens == null)
			return null;
		final errToken = tokens?.getTokenAtOffset(document.offsetAt(errPos));
		if (errToken == null)
			return null;
		final prev = getPrevNonCommentSibling(errToken);
		// hard to scan #blocks for missing ; prev line
		if (prev == null || prev.tok.match(Sharp(_)))
			return null;
		final last = getLastNonCommentToken(prev);
		final pos = last.getPos();
		return document.rangeAt(pos.max, pos.max, Utf8);
	}

	static function getPrevNonCommentSibling(token:Null<TokenTree>):Null<TokenTree> {
		do {
			token = token?.previousSibling;
		} while (token?.isComment() == true);
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
			if (child?.isComment() == false)
				return child;
		}
		return null;
	}

	static function isAnonStructure(brToken:TokenTree):Bool {
		if (brToken.tok == BrClose)
			brToken = brToken.parent ?? return false;
		final first = brToken?.getFirstChild() ?? return false;
		final colon = first.getFirstChild() ?? return false;
		if (colon.tok.match(DblDot) && !colon.nextSibling?.tok.match(Semicolon)) {
			return true;
		}
		return false;
	}

	static function isAnonStructureField(token:TokenTree):Bool {
		final parent = token.parent ?? return false;
		if (!isAnonStructure(parent))
			return false;
		final colon = token.getFirstChild() ?? return false;
		return colon.tok.match(DblDot);
	}
}

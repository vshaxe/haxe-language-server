package haxeLanguageServer.features.haxe.codeAction.diagnostics;

import haxeLanguageServer.features.haxe.DiagnosticsFeature.DiagnosticKind;
import haxeLanguageServer.features.haxe.codeAction.CodeActionFeature;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.helper.FormatterHelper;
import haxeLanguageServer.helper.SemVer;
import languageServerProtocol.Types.CodeAction;
import tokentree.TokenTree;

class UpdateSyntaxActions {
	public static function createUpdateSyntaxActions(context:Context, params:CodeActionParams, existingActions:Array<CodeAction>):Array<CodeAction> {
		if (!(context.haxeServer.haxeVersion >= new SemVer(4, 3, 0)))
			return [];
		final uri = params.textDocument.uri;
		final doc = context.documents.getHaxe(uri) ?? return [];
		final actions:Array<CodeAction> = [];
		final token = doc.tokens!.getTokenAtOffset(doc.offsetAt(params.range.start));
		if (token == null)
			return [];

		final ifToken = getSingleLineIfExpr(token);
		if (ifToken != null) {
			final ifVarRange = getIfVarEqNullIdentRange(doc, ifToken);
			if (ifVarRange != null) {
				final ifVarName = doc.getText(ifVarRange);
				// `var a = b; if (a == null) a = c` to
				// `var a = b ?? c`
				addNullCoalPrevLineAction(context, params, actions, doc, ifToken, ifVarName);
				// `if (a == null) a = b` to
				// `a ??= b`
				addNullCoalAssignAction(context, params, actions, doc, ifToken, ifVarName);
			}

			final ifVarRange = getIfVarNotEqNullIdentRange(doc, ifToken);
			if (ifVarRange != null) {
				final ifVarName = doc.getText(ifVarRange);
				// `if (a.b != null) a.b.c` to
				// `a.b?.c`
				addSaveNavIfNotNullAction(context, params, actions, doc, ifToken, ifVarName);
			}
		}

		final questionToken = getNullCheckTernaryExpr(token);
		if (questionToken != null) {
			// `a == null ? 0 : a` to
			// `a ?? 0`
			addTernaryNullCheckAction(context, params, actions, doc, questionToken);
		}

		return actions;
	}

	static function addNullCoalPrevLineAction(context:Context, params:CodeActionParams, actions:Array<CodeAction>, doc:HaxeDocument, ifToken:TokenTree,
			ifVarName:String) {
		final prev = ifToken.previousSibling ?? return;
		final varIdent = getIdentAssignToken(doc, prev) ?? return;
		final varIdentEnd = getIdentEnd(varIdent);
		final varIdentRange = doc.rangeAt(varIdent.pos, Utf8).union(doc.rangeAt(varIdentEnd.pos, Utf8));
		final varNameName = doc.getText(varIdentRange);
		if (varNameName != ifVarName)
			return;
		final ranges = getIfBodyVarAssignRanges(doc, ifToken);
		if (ranges != null) {
			final varName = doc.getText(ranges.varName);
			if (ifVarName != varName)
				return;
		}
		final valueRange = ranges!.value ?? getIfBodyDeadEndRange(doc, ifToken) ?? return;
		var value = doc.getText(valueRange);
		if (!value.endsWith(";"))
			value += ";";
		final prevValueToken = varIdent.getFirstChild()!.getFirstChild() ?? return;
		final prevValueRange = doc.rangeAt(prevValueToken.getPos(), Utf8);
		final prevValue = doc.getText(prevValueRange);
		final replaceRange = prevValueRange.union(doc.rangeAt(ifToken.getPos(), Utf8));
		actions.push({
			title: "Change to ?? operator",
			kind: QuickFix,
			edit: WorkspaceEditHelper.create(context, params, [
				{
					range: replaceRange,
					newText: '$prevValue ?? ${multilineIndent(doc, context, value, replaceRange.start)}'
				}
			]),
		});
	}

	static function multilineIndent(doc:HaxeDocument, context:Context, value:String, pos:Position):String {
		if (!value.contains("\n"))
			return value;
		value = FormatterHelper.formatText(doc, context, value, ExpressionLevel);
		final line = doc.lineAt(pos.line);
		final count = lineIndentationCount(line);
		if (count == 0)
			return value;
		final prefix = "".rpad(line.charAt(0), count);
		value = value.split("\n").mapi((i, s) -> i == 0 ? s : '$prefix$s').join("\n");
		return value;
	}

	static function lineIndentationCount(s:String):Int {
		var spaces = 0;
		for (i => _ in s) {
			if (!s.isSpace(i))
				break;
			spaces++;
		}
		return spaces;
	}

	static function addNullCoalAssignAction(context:Context, params:CodeActionParams, actions:Array<CodeAction>, doc:HaxeDocument, ifToken:TokenTree,
			ifVarName:String) {
		final ranges = getIfBodyVarAssignRanges(doc, ifToken) ?? return;
		final varName = doc.getText(ranges.varName);
		if (ifVarName != varName)
			return;
		var value = doc.getText(ranges.value);
		if (!value.endsWith(";"))
			value += ";";
		final replaceRange = doc.rangeAt(ifToken.getPos(), Utf8);
		actions.push({
			title: "Change to ??= operator",
			kind: QuickFix,
			edit: WorkspaceEditHelper.create(context, params, [
				{
					range: replaceRange,
					newText: '$ifVarName ??= ${multilineIndent(doc, context, value, replaceRange.start)}'
				}
			]),
		});
	}

	static function addSaveNavIfNotNullAction(context:Context, params:CodeActionParams, actions:Array<CodeAction>, doc:HaxeDocument, ifToken:TokenTree,
			ifVarName:String) {
		final ident = getSingleLineIfBodyExpr(ifToken) ?? return;
		final varName = doc.getText(doc.rangeAt(ident.getPos(), Utf8));
		if (!varName.startsWith(ifVarName))
			return;
		var accessPart = varName.replace(ifVarName, "");
		if (!accessPart.startsWith("?.")) {
			if (!accessPart.startsWith("."))
				return;
			accessPart = '?$accessPart';
		}
		if (!accessPart.endsWith(";"))
			accessPart += ";";
		final replaceRange = doc.rangeAt(ifToken.getPos(), Utf8);
		actions.push({
			title: "Change to ?. operator",
			kind: QuickFix,
			edit: WorkspaceEditHelper.create(context, params, [
				{
					range: replaceRange,
					newText: '$ifVarName$accessPart'
				}
			]),
		});
	}

	static function addTernaryNullCheckAction(context:Context, params:CodeActionParams, actions:Array<CodeAction>, doc:HaxeDocument, questionToken:TokenTree) {
		final binopToken = questionToken.parent!.parent ?? return;
		final ifIdentEnd = binopToken.parent ?? return;
		final ifIdentStart = preDotToken(ifIdentEnd);

		final firstOpStart = questionToken.getFirstChild() ?? return;
		final colon = firstOpStart.nextSibling ?? return;
		final secondOpStart = colon.getFirstChild() ?? return;
		final secondOpEnd = getLastNonCommaToken(secondOpStart) ?? return;

		final ifIdentRange = doc.rangeAt(ifIdentStart.pos).union(doc.rangeAt(ifIdentEnd.pos));
		final firstRange = doc.rangeAt(firstOpStart.getPos());
		final secondRange = doc.rangeAt(secondOpStart.pos).union(doc.rangeAt(secondOpEnd.pos));
		final isEq = binopToken.matches(Binop(OpEq));

		final condText = doc.getText(ifIdentRange);
		final firstText = doc.getText(firstRange);
		final secondText = doc.getText(secondRange);
		if (isEq) {
			if (condText != secondText)
				return;
		} else {
			if (condText != firstText)
				return;
		}
		final replaceRange = doc.rangeAt(ifIdentStart.getPos());
		var value = isEq ? firstText : secondText;
		if (!value.endsWith(";"))
			value += ";";
		actions.push({
			title: "Change to ?? operator",
			kind: QuickFix,
			edit: WorkspaceEditHelper.create(context, params, [
				{
					range: replaceRange,
					newText: '$condText ?? ${multilineIndent(doc, context, value, replaceRange.start)}'
				}
			]),
		});
	}

	static function getIdentAssignToken(doc:HaxeDocument, ident:TokenTree):Null<TokenTree> {
		if (ident.tok.match(Kwd(KwdVar | KwdFinal))) {
			ident = ident.getFirstChild() ?? cast return null;
		}
		final identEnd = getIdentEnd(ident);
		final opEq = identEnd.getFirstChild() ?? cast return null;
		switch opEq.tok {
			case Binop(OpAssign):
				return ident;
			case _:
				return null;
		}
	}

	static function getIfBodyDeadEndRange(doc:HaxeDocument, ifToken:TokenTree):Null<Range> {
		var ident = getSingleLineIfBodyExpr(ifToken) ?? cast return null;
		switch ident.tok {
			case Kwd(KwdReturn | KwdBreak | KwdContinue | KwdThrow):
				return doc.rangeAt(ident.getPos(), Utf8);
			case _:
				return null;
		}
	}

	static function getSingleLineIfExpr(token:Null<TokenTree>):Null<TokenTree> {
		// enough to find `if` parent for single-line cases
		for (i in 0...10) {
			if (token == null)
				return null;
			if (token.tok.match(Kwd(KwdIf)))
				return token;
			token = token.parent;
		}
		return null;
	}

	static function getNullCheckTernaryExpr(token:Null<TokenTree>):Null<TokenTree> {
		for (i in 0...10) {
			if (token == null)
				return null;
			if (token.tok.match(Binop(OpEq | OpNotEq))) {
				final kwdNull = token.getFirstChild() ?? cast return null;
				if (kwdNull.matches(Kwd(KwdNull)) == false)
					return null;
				final questionToken = kwdNull.getFirstChild() ?? cast return null;
				if (questionToken!.matches(Question) == false)
					return null;
				return questionToken;
			}
			token = token.parent;
		}
		return null;
	}

	static function getTernaryNullCheckRanges(questionToken:TokenTree):Null<{ifVar:Range, ifNull:Range, ifNotNull:Range}> {
		final t = questionToken.access()
			.firstChild()
			.matches(Kwd(KwdNull))
			.nextSibling()
			.matches(Question)
			.child(1)
			.matches(DblDot);
		if (t.exists() == false)
			return null;
		return null;
	}

	static function getIfVarEqNullIdentRange(doc:HaxeDocument, ifToken:TokenTree):Null<Range> {
		final pOpen = ifToken.getFirstChild() ?? cast return null;
		final ident = pOpen.getFirstChild() ?? cast return null;
		final identEnd = getIdentEnd(ident);
		final opEq = identEnd.getFirstChild() ?? cast return null;
		final kwdNull = opEq.getFirstChild() ?? cast return null;
		switch [opEq.tok, kwdNull.tok] {
			case [Binop(OpEq), Kwd(KwdNull)]:
				return doc.rangeAt(ident.pos, Utf8).union(doc.rangeAt(identEnd.pos, Utf8));
			case _:
				return null;
		}
	}

	static function getIfVarNotEqNullIdentRange(doc:HaxeDocument, ifToken:TokenTree):Null<Range> {
		final pOpen = ifToken.getFirstChild() ?? cast return null;
		final ident = pOpen.getFirstChild() ?? cast return null;
		final identEnd = getIdentEnd(ident);
		final opNotEq = identEnd.getFirstChild() ?? cast return null;
		final kwdNull = opNotEq.getFirstChild() ?? cast return null;
		switch [opNotEq.tok, kwdNull.tok] {
			case [Binop(OpNotEq), Kwd(KwdNull)]:
				return doc.rangeAt(ident.pos, Utf8).union(doc.rangeAt(identEnd.pos, Utf8));
			case _:
				return null;
		}
	}

	static function getIfBodyVarAssignRanges(doc:HaxeDocument, ifToken:TokenTree):Null<{varName:Range, value:Range}> {
		var ident2 = getSingleLineIfBodyExpr(ifToken) ?? cast return null;
		final ident2End = getIdentEnd(ident2);
		final opAssign = ident2End.getFirstChild() ?? cast return null;
		final value = opAssign.getFirstChild() ?? cast return null;
		switch opAssign.tok {
			case Binop(OpAssign):
				return {
					varName: doc.rangeAt(ident2.pos, Utf8).union(doc.rangeAt(ident2End.pos, Utf8)),
					value: doc.rangeAt(value.getPos(), Utf8)
				};
			case _:
				return null;
		}
	}

	static function getSingleLineIfBodyExpr(ifToken:TokenTree):Null<TokenTree> {
		var ident = ifToken.access().child(1)!.token ?? cast return null;
		if (ident.matches(BrOpen)) {
			final children = ident.children ?? cast return null;
			if (children.length > 2) // expr and BrClose
				return null;
			ident = ident.getFirstChild() ?? cast return null;
		}
		return ident;
	}

	static function getIdentEnd(ident:TokenTree):TokenTree {
		final child = ident.getFirstChild() ?? return ident;
		if (child.tok.match(Dot | QuestionDot | Question | Const(CIdent(_))))
			return getIdentEnd(child);
		return ident;
	}

	static function preDotToken(token:TokenTree):TokenTree {
		final parent = token.parent ?? return token;
		switch parent.tok {
			case Kwd(KwdNew):
				return parent;
			case QuestionDot, Dot:
				final prevToken = parent.parent ?? return token;
				if (!token.isCIdent())
					return token;
				return preDotToken(prevToken);
			case _:
		}
		return token;
	}

	static function getLastToken(token:Null<TokenTree>):Null<TokenTree> {
		if (token == null)
			return null;
		return TokenTreeCheckUtils.getLastToken(token);
	}

	static function getLastNonCommaToken(token:Null<TokenTree>):Null<TokenTree> {
		var last = getLastToken(token);
		if (last == null)
			return last;
		if (last.tok == Comma || last.tok == Semicolon) {
			last = last.previousSibling ?? return last.parent;
			// [Dot(...), Semicolon] case
			return getLastNonCommaToken(last);
		}
		return last;
	}
}

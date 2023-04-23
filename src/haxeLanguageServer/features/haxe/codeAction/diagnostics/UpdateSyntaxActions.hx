package haxeLanguageServer.features.haxe.codeAction.diagnostics;

import haxeLanguageServer.features.haxe.DiagnosticsFeature.DiagnosticKind;
import haxeLanguageServer.features.haxe.codeAction.CodeActionFeature;
import haxeLanguageServer.features.haxe.codeAction.OrganizeImportsFeature;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.helper.FormatterHelper;
import languageServerProtocol.Types.CodeAction;
import tokentree.TokenTree;

class UpdateSyntaxActions {
	public static function createUpdateSyntaxActions(context:Context, params:CodeActionParams, existingActions:Array<CodeAction>):Array<CodeAction> {
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

		return actions;
	}

	static function addNullCoalPrevLineAction(context:Context, params:CodeActionParams, actions:Array<CodeAction>, doc:HaxeDocument, ifToken:TokenTree,
			ifVarName:String) {
		final prev = ifToken.previousSibling ?? return;
		final varIdent = getIdentAssignToken(doc, prev) ?? return;
		final varIdentEnd = getIdentEnd(varIdent);
		final varIdentRange = doc.rangeAt(varIdent.pos).union(doc.rangeAt(varIdentEnd.pos));
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
		final prevValueRange = doc.rangeAt(prevValueToken.getPos());
		final prevValue = doc.getText(prevValueRange);
		final replaceRange = prevValueRange.union(doc.rangeAt(ifToken.getPos()));
		actions.push({
			title: "Change to ?? operator",
			kind: QuickFix,
			edit: WorkspaceEditHelper.create(context, params, [
				{
					range: replaceRange,
					newText: '$prevValue ?? $value'
					// newText: FormatterHelper.formatText(doc, context, '$ifName ??= $value', ExpressionLevel);
				}
			]),
		});
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
		final replaceRange = doc.rangeAt(ifToken.getPos());
		actions.push({
			title: "Change to ??= operator",
			kind: QuickFix,
			edit: WorkspaceEditHelper.create(context, params, [
				{
					range: replaceRange,
					newText: '$ifVarName ??= $value'
					// newText: FormatterHelper.formatText(doc, context, '$ifName ??= $value', ExpressionLevel);
				}
			]),
		});
	}

	static function addSaveNavIfNotNullAction(context:Context, params:CodeActionParams, actions:Array<CodeAction>, doc:HaxeDocument, ifToken:TokenTree,
			ifVarName:String) {
		final ident = getSingleLineIfBodyExpr(ifToken) ?? return;
		final varName = doc.getText(doc.rangeAt(ident.getPos()));
		if (!varName.startsWith(ifVarName))
			return;
		var accessPart = varName.replace(ifVarName, "");
		trace(varName, ifVarName);
		if (!accessPart.startsWith("?.")) {
			if (!accessPart.startsWith("."))
				return;
			accessPart = '?$accessPart';
		}
		if (!accessPart.endsWith(";"))
			accessPart += ";";
		final replaceRange = doc.rangeAt(ifToken.getPos());
		actions.push({
			title: "Change to ?. operator",
			kind: QuickFix,
			edit: WorkspaceEditHelper.create(context, params, [
				{
					range: replaceRange,
					newText: '$ifVarName$accessPart'
					// newText: FormatterHelper.formatText(doc, context, '$ifName ??= $value', ExpressionLevel);
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
				return doc.rangeAt(ident.getPos());
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

	static function getIfVarEqNullIdentRange(doc:HaxeDocument, ifToken:TokenTree):Null<Range> {
		final pOpen = ifToken.getFirstChild() ?? cast return null;
		final ident = pOpen.getFirstChild() ?? cast return null;
		final identEnd = getIdentEnd(ident);
		final opEq = identEnd.getFirstChild() ?? cast return null;
		final kwdNull = opEq.getFirstChild() ?? cast return null;
		switch [opEq.tok, kwdNull.tok] {
			case [Binop(OpEq), Kwd(KwdNull)]:
				return doc.rangeAt(ident.pos).union(doc.rangeAt(identEnd.pos));
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
				return doc.rangeAt(ident.pos).union(doc.rangeAt(identEnd.pos));
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
					varName: doc.rangeAt(ident2.pos).union(doc.rangeAt(ident2End.pos)),
					value: doc.rangeAt(value.getPos())
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
		if (child.tok.match(Dot | Question | Const(CIdent(_))))
			return getIdentEnd(child);
		return ident;
	}
}

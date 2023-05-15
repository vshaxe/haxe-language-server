package codeActions;

import haxeLanguageServer.features.haxe.codeAction.diagnostics.ParserErrorActions;

@:access(haxeLanguageServer.features.haxe.codeAction.diagnostics.ParserErrorActions)
class FixParserErrorTest extends DisplayTestCase {
	/**
		function main() {
			var x = 0
		{-1-}}
		---
		function main() {
			var x = 0;
		}
	**/
	function testSemicolon():Void {
		final params = codeActionParams(pos(1).toRange());
		final diag = createDiagnostic(pos(1).toRange());
		final actions = [];
		ParserErrorActions.createMissingSemicolonAction(ctx.context, params, diag, actions);
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			{[]{-1-}}
			trace(1){-2-});
		}
		---
		function main() {
			{[];}
			trace(1););
		}
	**/
	function testOnelines():Void {
		for (i in [2, 1]) {
			final params = codeActionParams(pos(i).toRange());
			final diag = createDiagnostic(pos(i).toRange());
			final actions = [];
			ParserErrorActions.createMissingSemicolonAction(ctx.context, params, diag, actions);
			applyTextEdit(actions[0].edit);
		}
		eq(ctx.result, ctx.doc.content);
	}
}

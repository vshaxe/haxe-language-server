package codeActions;

import haxeLanguageServer.features.haxe.codeAction.diagnostics.UpdateSyntaxActions;

@:access(haxeLanguageServer.features.haxe.codeAction.diagnostics.UpdateSyntaxActions)
class IfInvertTest extends DisplayTestCase {
	/**
		class Main {
			static function main() {
				final obj = {flag: true};
				while (false) {
					if (obj.flag) {{-1-}
						trace("not last expr, ignore");
					}
					if (obj.flag) {{-2-}
						trace(123);
					}
				}
			}
		}
		---
		class Main {
			static function main() {
				final obj = {flag: true};
				while (false) {
					if (obj.flag) {
						trace("not last expr, ignore");
					}
					if (!obj.flag) continue;
					trace(123);
				}
			}
		}
	**/
	function testWhileTwoExprs() {
		final actions = UpdateSyntaxActions.createUpdateSyntaxActions(ctx.context, codeActionParams(pos(1).toRange()), []);
		arrayEq(actions, []);
		final actions = UpdateSyntaxActions.createUpdateSyntaxActions(ctx.context, codeActionParams(pos(2).toRange()), []);
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			do {
				if (obj.flag == true && !obj.flag == true) {{-1-}
					trace(123);
				} else {
					trace("gen before return");
				}
			} while (false);
		}
		---
		function main() {
			do {
				if (obj.flag != true || obj.flag == true) {
					trace("gen before return");
					continue;
				}
				trace(123);
			} while (false);
		}
	**/
	function testDoWhileIfElse():Void {
		final actions = UpdateSyntaxActions.createUpdateSyntaxActions(ctx.context, codeActionParams(pos(1).toRange()), []);
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			if (true) {{-1-}
				trace("not last expr, ignore");
			}

			if{-2-} (obj.flag && (obj.flag == true) && obj.flag && arr[0] == 0) {
				trace(123);
			}
		}
		---
		function main() {
			if (true) {
				trace("not last expr, ignore");
			}

			if (!obj.flag || !(obj.flag == true) || !obj.flag || arr[0] != 0) return;
			trace(123);
		}
	**/
	function testTwoIfs():Void {
		final actions = UpdateSyntaxActions.createUpdateSyntaxActions(ctx.context, codeActionParams(pos(1).toRange()), []);
		arrayEq(actions, []);
		final actions = UpdateSyntaxActions.createUpdateSyntaxActions(ctx.context, codeActionParams(pos(2).toRange()), []);
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			for (i in []) {
				if (false) {{-1-}
					return 0;
				}
			}

			if (true) {{-2-}
				trace(123);
				return 1;
			} else {
				trace("gen before return");
				return 0;
			}
		}
		---
		function main() {
			for (i in []) {
				if (true) continue;
				return 0;
			}

			if (false) {
				trace("gen before return");
				return 0;
			}
			trace(123);
			return 1;
		}
	**/
	function testIfElseWithReturns():Void {
		final actions = UpdateSyntaxActions.createUpdateSyntaxActions(ctx.context, codeActionParams(pos(2).toRange()), []);
		applyTextEdit(actions[0].edit);
		final actions = UpdateSyntaxActions.createUpdateSyntaxActions(ctx.context, codeActionParams(pos(1).toRange()), []);
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			if (1 == 1) {{-1-}
				trace(1);
				if (2 == 2) {
					trace(2);
				} else {
					trace("beforefoo2");
				}
			} else {
				trace("beforefoo");
			}
			throw "foo";
		}
		---
		function main() {
			if (1 != 1) {
				trace("beforefoo");
				throw "foo";
			}
			trace(1);
			if (2 == 2) {
				trace(2);
			} else {
				trace("beforefoo2");
			}
			throw "foo";
		}
	**/
	function testExceptions():Void {
		final actions = UpdateSyntaxActions.createUpdateSyntaxActions(ctx.context, codeActionParams(pos(1).toRange()), []);
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			if (1 != 1) {
				trace("beforefoo");
				throw "foo";
			}
			trace(1);
			if (2 == 2) {{-1-}
				trace(2);
			} else {
				trace("beforefoo2");
			}
			throw "foo";
		}
		---
		function main() {
			if (1 != 1) {
				trace("beforefoo");
				throw "foo";
			}
			trace(1);
			if (2 != 2) {
				trace("beforefoo2");
				throw "foo";
			}
			trace(2);
			throw "foo";
		}
	**/
	function testExceptions2():Void {
		final actions = UpdateSyntaxActions.createUpdateSyntaxActions(ctx.context, codeActionParams(pos(1).toRange()), []);
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}
}

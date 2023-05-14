package codeActions;

import haxeLanguageServer.features.haxe.codeAction.diagnostics.UpdateSyntaxActions;

@:access(haxeLanguageServer.features.haxe.codeAction.diagnostics.UpdateSyntaxActions)
class UpdateNullCheckTest extends DisplayTestCase {
	/**
		function main() {
			var foo = {name: null};
			var bar = {name: 0};
			foo.name = foo.name == null{-1-} ? bar.name : foo.name;
			foo.name = foo.name != null{-2-} ? foo.name : bar.name;
			foo.name = foo.name == null{-3-} ? {
				name: 0
			}.name : foo.name; // comment
			// should not work
			foo.name = foo.name == null{-4-} ? foo.name : bar.name;
			foo.name = foo.name != null{-5-} ? bar.name : foo.name;
		}
		---
		function main() {
			var foo = {name: null};
			var bar = {name: 0};
			foo.name = foo.name ?? bar.name;
			foo.name = foo.name ?? bar.name;
			foo.name = foo.name ?? {
				name: 0
			}.name;
			 // comment
			// should not work
			foo.name = foo.name == null ? foo.name : bar.name;
			foo.name = foo.name != null ? bar.name : foo.name;
		}
	**/
	function testWhileTwoExprs() {
		final actions = UpdateSyntaxActions.createUpdateSyntaxActions(ctx.context, codeActionParams(pos(5).toRange()), []);
		arrayEq(actions, []);
		final actions = UpdateSyntaxActions.createUpdateSyntaxActions(ctx.context, codeActionParams(pos(4).toRange()), []);
		arrayEq(actions, []);
		for (id in [3, 2, 1]) {
			final actions = UpdateSyntaxActions.createUpdateSyntaxActions(ctx.context, codeActionParams(pos(id).toRange()), []);
			applyTextEdit(actions[0].edit);
		}
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			var date = null;
			date.time = calc.time();
			if (date.time == null) date.time = some.value;{-1-}
			if (date.time != null) date.time.seconds = 0;{-2-}
			if (date.time != null) date.time2.seconds = 0;{-3-}
		}
		---
		function main() {
			var date = null;
			date.time = calc.time();
			date.time ??= some.value;
			date.time?.seconds = 0;
			if (date.time == null) return;
			date.time2.seconds = 0;
		}
	**/
	function testMultipleUpdates() {
		final actions = UpdateSyntaxActions.createUpdateSyntaxActions(ctx.context, codeActionParams(pos(3).toRange()), []);
		arrayEq(actions.filter(a -> a.title == "Change to ?. operator"), []);

		applyTextEdit(actions.find(a -> a.title == "Invert if expression").edit);

		final actions = UpdateSyntaxActions.createUpdateSyntaxActions(ctx.context, codeActionParams(pos(2).toRange()), []);
		applyTextEdit(actions[0].edit);

		final actions = UpdateSyntaxActions.createUpdateSyntaxActions(ctx.context, codeActionParams(pos(1).toRange()), []);
		applyTextEdit(actions.find(a -> a.title == "Change to ??= operator").edit);

		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			var date = null;
			date.time = calc.time();
			if (date.time == null) date.time = some.value;{-1-}
		}
		---
		function main() {
			var date = null;
			date.time = calc.time() ?? some.value;
		}
	**/
	function testIfNullCoal() {
		final actions = UpdateSyntaxActions.createUpdateSyntaxActions(ctx.context, codeActionParams(pos(1).toRange()), []);
		applyTextEdit(actions.find(a -> a.title == "Change to ?? operator").edit);
		eq(ctx.result, ctx.doc.content);
	}
}

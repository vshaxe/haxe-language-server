package codeActions;

import haxeLanguageServer.features.haxe.codeAction.diagnostics.MissingArgumentsAction;
import js.lib.Promise;

@:access(haxeLanguageServer.features.haxe.codeAction.diagnostics.MissingArgumentsAction)
class AddMissingArgsTest extends DisplayTestCase {
	/**
		function main() {
			var x = {y: 1};
			foo(x{-1-}.y);
		}
		function foo() {}
		---
		function main() {
			var x = {y: 1};
			foo(x.y);
		}
		function foo(y:Int) {}
	**/
	@:timeout(500)
	function test(async:utest.Async) {
		var action:CodeAction = {title: ""};
		final params = codeActionParams(pos(1).toRange());
		final diag = createDiagnostic(pos(1).toRange());
		final action:Null<Promise<CodeAction>> = MissingArgumentsAction.createMissingArgumentsAction(ctx.context, action, params, diag);
		assert(action != null);
		async.done();
		// TODO hangs on gotoDefinition request, needs more client simulation hacks in DisplayTestContext
		// action.then(action -> {
		// 	applyTextEdit(action.edit);
		// 	eq(ctx.result, ctx.doc.content);
		// 	async.done();
		// }, (err) -> {
		// 	throw err;
		// });
	}
}

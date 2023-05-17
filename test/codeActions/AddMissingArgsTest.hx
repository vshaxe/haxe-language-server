package codeActions;

import haxeLanguageServer.features.haxe.codeAction.diagnostics.MissingArgumentsAction;
import js.lib.Promise;

@:access(haxeLanguageServer.features.haxe.codeAction.diagnostics.MissingArgumentsAction)
class AddMissingArgsTest extends DisplayTestCase {
	/**
		function main() {
			var x = {y: 1};
			foo({-1-}x.y{-2-});
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
		ctx.cacheFile();
		ctx.startServer(() -> {
			var action:CodeAction = {title: ""};
			// diagnostics selects full arg range
			final params = codeActionParams(range(1, 2));
			final diag = createDiagnostic(range(1, 2));
			final action:Null<Promise<CodeAction>> = MissingArgumentsAction.createMissingArgumentsAction(ctx.context, action, params, diag);
			assert(action != null);
			action.then(action -> {
				ctx.removeCacheFile();
				applyTextEdit(action.edit);
				eq(ctx.result, ctx.doc.content);
				async.done();
			}, (err) -> {
				ctx.removeCacheFile();
				throw err;
			});
		});
	}
}

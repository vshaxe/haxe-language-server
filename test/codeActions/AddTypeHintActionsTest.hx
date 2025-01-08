package codeActions;

import haxeLanguageServer.features.haxe.codeAction.diagnostics.AddTypeHintActions;
import haxeLanguageServer.features.haxe.codeAction.diagnostics.MissingArgumentsAction;
import js.lib.Promise;

@:access(haxeLanguageServer.features.haxe.codeAction.diagnostics.MissingArgumentsAction)
class AddTypeHintActionsTest extends DisplayTestCase {
	/**
		class Main {
			final conf{-5-}ig = {
				x: 1,
				y: foo(0)
			}
			static function main() {
				final a{-4-}rr = [];
				arr.push(0);
				final first = arr[0];
				final co{-3-}rds = [{
					x: 0.0,
					y: 0.0,
					scale: 0.5
				}];
			}
			static function f{-1-}oo(a{-2-}rg, ?b:()->Void) {
				arg += 1;
				return () -> 1;
			}
		}
		---
		class Main {
			final config:{x:Int, y:() -> Int} = {
				x: 1,
				y: foo(0)
			}
			static function main() {
				final arr:Array<Int> = [];
				arr.push(0);
				final first = arr[0];
				final cords:Array<{x:Float, y:Float, scale:Float}> = [{
					x: 0.0,
					y: 0.0,
					scale: 0.5
				}];
			}
			static function foo(arg:Int, ?b:()->Void):() -> Int {
				arg += 1;
				return () -> 1;
			}
		}
	**/
	@:timeout(5000)
	function test(async:utest.Async) {
		ctx.cacheFile();
		ctx.startServer(() -> {
			var action:CodeAction = {title: ""};
			final ranges = [
				for (i in 1...6)
					range(i, i)
			];

			function pickAndApply(callback:() -> Void):Void {
				if (ranges.length == 0) {
					callback();
					return;
				}
				final range = ranges.shift();
				final params = codeActionParams(range);
				// final diag = createDiagnostic(range);
				final action = AddTypeHintActions.createAddTypeHintAction(ctx.context, action, params);
				assert(action != null);
				action.then(action -> {
					applyTextEdit(action.edit);
					pickAndApply(callback);
				}, (err) -> {
					ctx.removeCacheFile();
					throw err;
				});
			}

			pickAndApply(() -> {
				eq(ctx.result, ctx.doc.content);
				ctx.removeCacheFile();
				async.done();
			});
		});
	}
}

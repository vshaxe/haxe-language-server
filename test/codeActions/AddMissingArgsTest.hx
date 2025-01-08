package codeActions;

import haxeLanguageServer.features.haxe.codeAction.diagnostics.MissingArgumentsAction;
import js.lib.Promise;

@:access(haxeLanguageServer.features.haxe.codeAction.diagnostics.MissingArgumentsAction)
class AddMissingArgsTest extends DisplayTestCase {
	/**
		import haxe.io.Bytes;
		function main() {
			var x = {y: 1};
			foo0(x);
			foo1(x.y);
			foo2({y: 0});
			foo3({y: 0}.y);
			foo4(() -> {});
			foo5(foo -> {});
			foo6(function() {});
			foo7(true);
			foo8(null);
			foo9(haxe.format.JsonParser.parse);
			foo10(bytes());
			foo11(new Bytes(10, null));
		}
		function bytes():Bytes return null;
		function foo0() {}
		function foo1() {}
		function foo2() {}
		function foo3() {}
		function foo4() {}
		function foo5() {}
		function foo6() {}
		function foo7() {}
		function foo8() {}
		function foo9() {}
		function foo10() {}
		function foo11() {}
		---
		import haxe.io.Bytes;
		function main() {
			var x = {y: 1};
			foo0(x);
			foo1(x.y);
			foo2({y: 0});
			foo3({y: 0}.y);
			foo4(() -> {});
			foo5(foo -> {});
			foo6(function() {});
			foo7(true);
			foo8(null);
			foo9(haxe.format.JsonParser.parse);
			foo10(bytes());
			foo11(new Bytes(10, null));
		}
		function bytes():Bytes return null;
		function foo0(x:{y:Int}) {}
		function foo1(y:Int) {}
		function foo2(obj:{y:Int}) {}
		function foo3(y:Int) {}
		function foo4(callback:() -> Void) {}
		function foo5(callback:(foo) -> Void) {}
		function foo6(callback:() -> Void) {}
		function foo7(bool:Bool) {}
		function foo8(arg) {}
		function foo9(parse:(str:String) -> Dynamic) {}
		function foo10(arg:Bytes) {}
		function foo11(arg:Bytes) {}
	**/
	@:timeout(10000)
	function test(async:utest.Async) {
		ctx.cacheFile();
		ctx.startServer(() -> {
			var action:CodeAction = {title: ""};
			// diagnostics selects full arg range
			final ranges = getRegexRanges(~/foo[0-9]+\((.+)\);/g).map(range -> {
				final match = ctx.doc.getText(range);
				range.start.character += match.indexOf("(") + 1;
				range.end.character -= ");".length;
				return range;
			});
			ranges.reverse();

			function pickAndApply(callback:() -> Void):Void {
				if (ranges.length == 0) {
					callback();
					return;
				}
				final range = ranges.shift();
				final params = codeActionParams(range);
				final diag = createDiagnostic(range);
				final action = MissingArgumentsAction.createMissingArgumentsAction(ctx.context, action, params, diag);
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

	/**
		function main() {
			foo(1, {-1-}2{-2-});
		}
		function foo(i:Int) {}
		---
		function main() {
			foo(1, 2);
		}
		function foo(i:Int, i2:Int) {}
	**/
	@:timeout(500)
	function testSecondIntArg(async:utest.Async) {
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

	/**
		function main() {
			new Foo({-1-}1{-2-});
		}
		class Foo {
			public function new() {}
		}
		---
		function main() {
			new Foo(1);
		}
		class Foo {
			public function new(i:Int) {}
		}
	**/
	@:timeout(1000)
	function testConstructorArg(async:utest.Async) {
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

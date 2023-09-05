package codeActions;

import haxeLanguageServer.features.haxe.codeAction.ExtractVarFeature;

@:access(haxeLanguageServer.features.haxe.codeAction.ExtractVarFeature)
class ExtractVarTest extends DisplayTestCase {
	/**
		class Main {
			function main() {
				var foo = "bar{-1-}";
				if (true)
					foo = "bar2{-2-}";
			}
		}
		---
		class Main {
			function main() {
				final bar = "bar";
				var foo = bar;
				final bar2 = "bar2";
				if (true)
					foo = bar2;
			}
		}
	**/
	function test() {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(2).toRange());
		applyTextEdit(actions[0].edit);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			[{f{-1-}: 1}{-2-}];
		}
		---
		function main() {
			final obj = {f: 1};
			[obj];
		}
	**/
	function testObject():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		arrayEq(actions, []);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(2).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		static function outerHeight(el:Element):Float {
			final style = window.getComputedStyle(el);
			return (el.getBoundingClientRect().height
				+ Std.pars{-1-}eFloat(style.marginTop)
				+ Std.parseFloat(style.marginBottom));
		}
		---
		static function outerHeight(el:Element):Float {
			final style = window.getComputedStyle(el);
			final parseFloat = Std.parseFloat(style.marginTop);
			return (el.getBoundingClientRect().height
				+ parseFloat
				+ Std.parseFloat(style.marginBottom));
		}
	**/
	function testReturnCall():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			final foo = add({
				onComplete: spr{-1-}ite -> {
					foo(1, [2]);
				}
			});
		}
		---
		function main() {
			final sprite = sprite -> {
				foo(1, [2]);
			};
			final foo = add({
				onComplete: sprite
			});
		}
	**/
	function testArrowFunction():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			final item1 = tasks[0]{-1-};
			final item2 = [1, 2, 3][0]{-2-};
			final item3 = call()[0]{-3-};
		}
		---
		function main() {
			final arr = tasks[0];
			final item1 = arr;
			final arr = [1, 2, 3][0];
			final item2 = arr;
			final arr = call()[0];
			final item3 = arr;
		}
	**/
	function testArrayAccess():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(3).toRange());
		applyTextEdit(actions[0].edit);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(2).toRange());
		applyTextEdit(actions[0].edit);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}
}

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
}

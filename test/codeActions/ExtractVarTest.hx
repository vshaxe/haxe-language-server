package codeActions;

import haxeLanguageServer.features.haxe.codeAction.ExtractVarFeature;

@:access(haxeLanguageServer.features.haxe.codeAction.ExtractVarFeature)
class ExtractVarTest extends DisplayTestCase {
	/**
		// абвг
		class Main {
			function main() {
				var foo = "bar{-1-}";
				if (true)
					foo = "bar2{-2-}";
			}
		}
		---
		// абвг
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

	/**
		function main() {
			if (obj.isTrue()) {
				game.st{-1-}art(function() {});
			} else {}
		}
		---
		function main() {
			if (obj.isTrue()) {
				final start = game.start(function() {});
				start;
			} else {}
		}
	**/
	function testStatementInBlock():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function call():Any {
			if (obj.isTrue() || obj.sub.is{-1-}True()) {
				return {a: () -> {}};
			} else if (obj.nope) {
				return {a: () -> {}};
			}
		}
		---
		function call():Any {
			final isTrue = obj.sub.isTrue();
			if (obj.isTrue() || isTrue) {
				return {a: () -> {}};
			} else if (obj.nope) {
				return {a: () -> {}};
			}
		}
	**/
	function testSecondIfCond():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			obj.sub.delayed(1000, () ->{-1-} {
				foo.value = 1;
			});
			obj.sub.delayed(1000, () -> {
				foo.value = 2;
			}{-2-});
			obj.sub.delayed({a: [1, {}]}, funct{-3-}ion() {
				foo.value = 3;
			});
		}
		---
		function main() {
			final callback = () -> {
				foo.value = 1;
			};
			obj.sub.delayed(1000, callback);
			final callback = () -> {
				foo.value = 2;
			};
			obj.sub.delayed(1000, callback);
			final callback = function() {
				foo.value = 3;
			};
			obj.sub.delayed({a: [1, {}]}, callback);
		}
	**/
	function testExtractAnonFunction():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(3).toRange());
		applyTextEdit(actions[0].edit);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(2).toRange());
		applyTextEdit(actions[0].edit);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function call():Bool {
			if (obj.isTrue() {-1-}|| obj.sub.isFalse) {
				return true;
			}
			return false;
		}
		---
		function call():Bool {
			final isFalse = obj.isTrue() || obj.sub.isFalse;
			if (isFalse) {
				return true;
			}
			return false;
		}
	**/
	function testExtractBinop():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			var last = fo{-1-}o(arr) ?? null;
		}
		---
		function main() {
			final foo = foo(arr);
			var last = foo ?? null;
		}
	**/
	function testExtractCallBeforeBinop():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			if (obj.f{-1-}oo == 200) {}
		}
		---
		function main() {
			final foo = obj.foo;
			if (foo == 200) {}
		}
	**/
	function testExtractDottedBeforeBinop():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			if ({-1-}obj.isTrue() || obj.sub.isFalse{-2-}) {}
		}
		---
		function main() {
			final isFalse = obj.isTrue() || obj.sub.isFalse;
			if (isFalse) {}
		}
	**/
	function testExtractIfConditionRangeWithParens():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, range(1, 2));
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			{-1-}bgObjects.add(trigger.obj);{-2-}
		}
		---
		function main() {
			final value = bgObjects.add(trigger.obj);
			value;
		}
	**/
	function testExtractSemicolonTrim():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, range(1, 2));
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			var x:I{-1-}nt = getValue();
			var ok = foo(arr) is Dyn{-2-}amic;
			foo((v : I{-3-}nt));
		}
	**/
	function testNoExtractOnTypes():Void {
		final feature = new ExtractVarFeature(ctx.context);
		eq(0, feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange()).length);
		eq(0, feature.extractVar(ctx.doc, ctx.uri, pos(2).toRange()).length);
		eq(0, feature.extractVar(ctx.doc, ctx.uri, pos(3).toRange()).length);
	}

	/**
		function main() {
			foo((v{-1-} : Any));
		}
		---
		function main() {
			final v = v;
			foo((v : Any));
		}
	**/
	function testTypeCheck():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			foo((ar{-1-}r[0] : Any));
		}
		---
		function main() {
			final arr = arr[0];
			foo((arr : Any));
		}
	**/
	function testTypeCheckArrayAccess():Void {
		final feature = new ExtractVarFeature(ctx.context);
		// extract the value `arr[0]`, keeping the `: Any` check in place
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			var last = true ? fo{-1-}o(arr) : false;
		}
		---
		function main() {
			final foo = foo(arr);
			var last = true ? foo : false;
		}
	**/
	function testExtractTernaryBranch():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			var last = isF{-1-}oo() ? foo(arr) : false;
		}
		---
		function main() {
			final isFoo = isFoo();
			var last = isFoo ? foo(arr) : false;
		}
	**/
	function testExtractTernaryCond():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			var x = "foo" i{-1-}s String;
			var y = "f{-2-}oo" is String;
		}
		---
		function main() {
			final string = "foo" is String;
			var x = string;
			final foo = "foo";
			var y = foo is String;
		}
	**/
	function testExtractIsOperator():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(2).toRange());
		applyTextEdit(actions[0].edit);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			var b = !isR{-1-}eady();
		}
		---
		function main() {
			final isReady = isReady();
			var b = !isReady;
		}
	**/
	function testExtractUnaryOperand():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			send(Colors.Bl{-1-}ack, null);
			obj.then(functi{-2-}on(res) {}, null);
		}
		---
		function main() {
			final black = Colors.Black;
			send(black, null);
			final callback = function(res) {};
			obj.then(callback, null);
		}
	**/
	function testExtractArgWithTrailingComma():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final b:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(2).toRange());
		applyTextEdit(b[0].edit);
		final a:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(a[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			switch x {
				case Dot, Question:
					if (parent.parent?.isCId{-1-}ent() == true) {}
				default:
			}
		}
		---
		function main() {
			switch x {
				case Dot, Question:
					final isCIdent = parent.parent?.isCIdent();
					if (isCIdent == true) {}
				default:
			}
		}
	**/
	function testExtractInSwitchCase():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			switch x {
				case Dot, Question if (foo ={-1-}= true):
				default:
			}
		}
		---
		function main() {
			final value = foo == true;
			switch x {
				case Dot, Question if (value):
				default:
			}
		}
	**/
	function testExtractSwitchCaseGuard():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			var x = ne{-1-}w Foo();
		}
		---
		function main() {
			final foo = new Foo();
			var x = foo;
		}
	**/
	function testExtractNewOnKeyword():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		function main() {
			trace(o{-1-}bj?.foo.bar);
		}
		---
		function main() {
			final bar = obj?.foo.bar;
			trace(bar);
		}
	**/
	function testExtractNameFromLastField():Void {
		final feature = new ExtractVarFeature(ctx.context);
		final actions:Array<CodeAction> = feature.extractVar(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}
}

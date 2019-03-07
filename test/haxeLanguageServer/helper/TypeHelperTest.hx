package haxeLanguageServer.helper;

import haxeLanguageServer.helper.TypeHelper.*;
import haxeLanguageServer.helper.TypeHelper;
import haxeLanguageServer.Configuration.FunctionFormattingConfig;

class TypeHelperTest extends Test {
	function testParseFunctionArgumentType() {
		var parsed = parseFunctionArgumentType("?Callback:Null<flixel.FlxObject -> ?String -> Void>");
		switch (parsed) {
			case DisplayType.DTFunction(args, ret):
				Assert.equals("flixel.FlxObject", args[0].type);
				Assert.isNull(args[0].opt);
				Assert.equals("String", args[1].type);
				Assert.isTrue(args[1].opt);
				Assert.equals(2, args.length);
				Assert.equals("Void", ret);
			case _:
				Assert.fail();
		}
	}

	function testParseFunctionArgumentTypeNestedNulls() {
		var parsed = parseFunctionArgumentType("foo:Null<Null<Null<Null<String -> Void>>>>");
		switch (parsed) {
			case DisplayType.DTFunction(args, ret):
				Assert.equals("String", args[0].type);
				Assert.equals(1, args.length);
				Assert.equals("Void", ret);
			case _:
				Assert.fail();
		}
	}

	function testPrintFunctionDeclaration() {
		assertPrintedEquals(parseFunctionArgumentType, "function(a:flixel.FlxObject, ?b:String):Void", "?Callback:Null<flixel.FlxObject -> ?String -> Void>",
			{argumentTypeHints: true, returnTypeHint: Always, useArrowSyntax: false});

		assertPrintedEquals(parseDisplayType, "function(a, b)", "String -> Bool -> Void>", {argumentTypeHints: false, returnTypeHint: Never, useArrowSyntax: false});

		assertPrintedEquals(parseDisplayType, "function(a:String, b:Bool)", "String -> Bool -> Void",
			{argumentTypeHints: true, returnTypeHint: NonVoid, useArrowSyntax: false});

		assertPrintedEquals(parseDisplayType, "function():String", "Void -> String", {argumentTypeHints: true, returnTypeHint: NonVoid, useArrowSyntax: false});
	}

	function testPrintArrowFunctionDeclaration() {
		function assert(expected, functionType, argumentTypeHints = false) {
			assertPrintedEquals(parseDisplayType, expected, functionType, {argumentTypeHints: argumentTypeHints, returnTypeHint: Always, useArrowSyntax: true});
		}

		assert("() ->", "Void -> Void");
		assert("() ->", "Void -> String");
		assert("a ->", "String -> Void");
		assert("(a:String) ->", "String -> Void", true);
		assert("(a:String, b:Bool) ->", "String -> Bool -> Void", true);
	}

	function assertPrintedEquals(parser:String->DisplayType, expected:String, functionType:String,
			formatting:FunctionFormattingConfig) {
		var parsed = parseFunctionArgumentType(functionType);
		switch (parsed) {
			case DisplayType.DTFunction(args, ret):
				var decl = printFunctionDeclaration(args, ret, formatting);
				Assert.equals(expected, decl);
			case _:
				Assert.fail();
		}
	}

	function testGetModule() {
		Assert.equals("Module", getModule("Module"));
		Assert.equals("Module", getModule("Module.Type"));

		Assert.equals("foo.bar.Module", getModule("foo.bar.Module"));
		Assert.equals("foo.bar.Module", getModule("foo.bar.Module.Type"));
	}
}

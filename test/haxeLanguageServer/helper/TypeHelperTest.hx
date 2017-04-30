package haxeLanguageServer.helper;

import haxeLanguageServer.helper.TypeHelper.*;
import haxeLanguageServer.helper.TypeHelper;

class TypeHelperTest extends TestCaseBase {
    function testParseFunctionArgumentType() {
        var parsed = parseFunctionArgumentType("?Callback:Null<flixel.FlxObject -> ?String -> Void>");
        switch (parsed) {
            case DisplayType.DTFunction(args, ret):
                assertEquals("flixel.FlxObject", args[0].type);
                assertFalse(args[0].opt);
                assertEquals("String", args[1].type);
                assertTrue(args[1].opt);
                assertEquals(2, args.length);
                assertEquals("Void", ret);
            case _:
                fail();
        }
    }

    function testParseFunctionArgumentTypeNestedNulls() {
        var parsed = parseFunctionArgumentType("foo:Null<Null<Null<Null<String -> Void>>>>");
        switch (parsed) {
            case DisplayType.DTFunction(args, ret):
                assertEquals("String", args[0].type);
                assertEquals(1, args.length);
                assertEquals("Void", ret);
            case f:
                fail();
        }
    }

    function testPrintFunctionDeclaration() {
        assertPrintedEquals(parseFunctionArgumentType,
            "function(a:flixel.FlxObject, ?b:String):Void",
            "?Callback:Null<flixel.FlxObject -> ?String -> Void>",
            {argumentTypeHints: true, returnTypeHint: Always, useArrowSyntax: false});

        assertPrintedEquals(parseDisplayType,
            "function(a, b)",
            "String -> Bool -> Void>",
            {argumentTypeHints: false, returnTypeHint: Never, useArrowSyntax: false});

        assertPrintedEquals(parseDisplayType,
            "function(a:String, b:Bool)",
            "String -> Bool -> Void",
            {argumentTypeHints: true, returnTypeHint: NonVoid, useArrowSyntax: false});

        assertPrintedEquals(parseDisplayType,
            "function():String",
            "Void -> String",
            {argumentTypeHints: true, returnTypeHint: NonVoid, useArrowSyntax: false});
    }

    function testPrintArrowFunctionDeclaration() {
        function assert(expected, functionType, argumentTypeHints = false) {
            assertPrintedEquals(parseDisplayType, expected, functionType,
                {argumentTypeHints: argumentTypeHints, returnTypeHint: Always, useArrowSyntax: true});
        }

        assert("() ->", "Void -> Void");
        assert("() ->", "Void -> String");
        assert("a ->", "String -> Void");
        assert("(a:String) ->", "String -> Void", true);
        assert("(a:String, b:Bool) ->", "String -> Bool -> Void", true);
    }

    function assertPrintedEquals(parser:String->DisplayType, expected:String, functionType:String, formatting:FunctionFormattingConfig) {
        var parsed = parseFunctionArgumentType(functionType);
        switch (parsed) {
            case DisplayType.DTFunction(args, ret):
                var decl = printFunctionDeclaration(args, ret, formatting);
                assertEquals(expected, decl);
            case _:
                fail();
        }
    }
}
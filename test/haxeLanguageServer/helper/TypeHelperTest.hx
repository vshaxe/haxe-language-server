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
            {argumentTypeHints: true, returnTypeHint: Always});

        assertPrintedEquals(parseDisplayType,
            "function(a, b)",
            "String -> Bool -> Void>",
            {argumentTypeHints: false, returnTypeHint: Never});

        assertPrintedEquals(parseDisplayType,
            "function(a:String, b:Bool)",
            "String -> Bool -> Void",
            {argumentTypeHints: true, returnTypeHint: NonVoid});

        assertPrintedEquals(parseDisplayType,
            "function():String",
            "Void -> String",
            {argumentTypeHints: true, returnTypeHint: NonVoid});
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
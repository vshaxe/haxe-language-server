package haxeLanguageServer.helper;

import haxeLanguageServer.helper.TypeHelper;

class TypeHelperTest extends TestCaseBase {
    function testParseFunctionArgumentType() {
        var parsed = TypeHelper.parseFunctionArgumentType("?Callback:Null<flixel.FlxObject -> ?String -> Void>");
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
        var parsed = TypeHelper.parseFunctionArgumentType("foo:Null<Null<Null<Null<String -> Void>>>>");
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
        var parsed = TypeHelper.parseFunctionArgumentType("?Callback:Null<flixel.FlxObject -> ?String -> Void>");
        switch (parsed) {
            case DisplayType.DTFunction(args, ret):
                var decl = TypeHelper.printFunctionDeclaration(args, ret);
                assertEquals("function(a:flixel.FlxObject, ?b:String):Void", decl);
            case _:
                fail();
        }
    }

    function testPrintFunctionDeclarationNullReturn() {
        var parsed = TypeHelper.parseFunctionArgumentType("?Callback:String -> Void");
        switch (parsed) {
            case DisplayType.DTFunction(args, ret):
                var decl = TypeHelper.printFunctionDeclaration(args);
                assertEquals("function(a:String)", decl);
            case _:
                fail();
        }
    }
}
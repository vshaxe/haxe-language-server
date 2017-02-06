package haxeLanguageServer.helper;

import haxeLanguageServer.helper.ArgumentNameHelper;
using haxeLanguageServer.helper.ArrayHelper;

class ArgumentNameHelperTest extends TestCaseBase {
    function testAvoidDuplicates() {
        function check(expected:Array<String>, original:Array<String>)
            assertTrue(expected.equals(ArgumentNameHelper.avoidDuplicates(original)));

        check(["a"], ["a"]);
        check(["b1", "b2"], ["b", "b"]);
    }

    function testGuessArgumentName() {
        function assert(expected, original, ?posInfos)
            assertEquals(expected, ArgumentNameHelper.guessArgumentName(original), posInfos);

        assert("object", "FlxObject");
        assert("f", "F");
        assert("params", "CodeActionParams");
        assert("case", "PascalCase");
        assert("int64", "__Int64");
        assert("f", "Float");
        assert("b", "Bool");
        assert("i", "Null<Null<Int>>");
        assert("s", "String");
        assert("unknown", null);
        assert("c", "C<Int,String>");
        assert("unknown", "<Int,String>");
    }
}
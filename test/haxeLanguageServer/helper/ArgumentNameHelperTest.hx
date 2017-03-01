package haxeLanguageServer.helper;

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

    function testAddNamesToSignatureType() {
        function assert(expected, original, ?posInfos)
            assertEquals(expected, ArgumentNameHelper.addNamesToSignatureType(original), posInfos);

        assert("a:Int", ":Int");
        assert("a:Int", "a:Int");

        assert("(a:Int, b:Int):Void", "(:Int, :Int):Void");
        assert("(a:Int, b:Int):Void", "(a:Int, b:Int):Void");
        assert("(a:Int, b:Int, c:Int):Void", "(:Int, :Int,:Int) : Void");

        assert("(", "(");

        // hopefully this is never needed...
        var letterOverflow = '(${[for (i in 0...30) ":Int"].join(", ")}):Void';
        var fixedSignature = ArgumentNameHelper.addNamesToSignatureType(letterOverflow);
        assertEquals(-1, fixedSignature.indexOf("{:")); // { comes after z in ascii
        assertEquals(2, fixedSignature.split(" b:").length); // arg names must be unique
    }
}
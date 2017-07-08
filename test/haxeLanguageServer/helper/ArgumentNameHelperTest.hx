package haxeLanguageServer.helper;

import haxeLanguageServer.helper.ArgumentNameHelper.*;

class ArgumentNameHelperTest extends TestCaseBase {
    function testAvoidDuplicates() {
        function check(expected:Array<String>, original:Array<String>)
            assertTrue(expected.equals(avoidDuplicates(original)));

        check(["a"], ["a"]);
        check(["b1", "b2"], ["b", "b"]);
    }

    function testGuessArgumentName() {
        function assert(expected, original, ?posInfos)
            assertEquals(expected, guessArgumentName(original), posInfos);

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
        assert("struct", "{}");
        assert("struct", "{ i : Int }");
    }

    function testAddNamesToSignatureType() {
        function assert(expected, original, ?posInfos)
            assertEquals(expected, addNamesToSignatureType(original), posInfos);

        function assertUnchanged(expectedAndOriginal, ?posInfos)
            assert(expectedAndOriginal, expectedAndOriginal, posInfos);

        assertUnchanged("String");

        assert("a:{ i : Int }", ":{ i : Int }");
        assert("a:{ i : Int, s : String }", ":{ i : Int, s : String }");
        assert("a:{}", ":{}");
        assert("(a:Int, b:{ s : String, i : Int }):Void", "(:Int, :{ s : String, i : Int }):Void");

        assert("a:Int", ":Int");
        assertUnchanged("a:Int");

        assert("(a:Int, b:Int):Void", "(:Int, :Int):Void");
        assert("(?a:Int, ?b:Int):Void", "(?:Int, ?:Int):Void");
        assertUnchanged("(a:Int, b:Int):Void");
        assert("(a:Int, b:Int, c:Int):Void", "(:Int, :Int,:Int) : Void");

        assertUnchanged("(");
        assertUnchanged("():haxe.ds.Option");
        assertUnchanged("():haxe.__Int64");
        assertUnchanged("():Array<Int>");
        assertUnchanged("():{ a:Int, b:Bool }");

        // hopefully this is never needed...
        var letterOverflow = '(${[for (i in 0...30) ":Int"].join(", ")}):Void';
        var fixedSignature = addNamesToSignatureType(letterOverflow);
        assertEquals(-1, fixedSignature.indexOf("{:")); // { comes after z in ascii
        assertEquals(2, fixedSignature.split(" b:").length); // arg names must be unique
    }
}
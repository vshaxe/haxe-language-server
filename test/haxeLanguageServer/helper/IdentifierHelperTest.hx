package haxeLanguageServer.helper;

import haxeLanguageServer.helper.IdentifierHelper.*;

class IdentifierHelperTest extends Test {
	function testAvoidDuplicates() {
		function check(expected:Array<String>, original:Array<String>)
			Assert.same(expected, avoidDuplicates(original));

		check(["a"], ["a"]);
		check(["b1", "b2"], ["b", "b"]);
	}

	function testGuessName() {
		function assert(expected, original, ?posInfos)
			Assert.equals(expected, guessName(original), posInfos);

		assert("object", "FlxObject");
		assert("f", "F");
		assert("params", "CodeActionParams");
		assert("case", "PascalCase");
		assert("int64", "__Int64");
		assert("f", "Float");
		assert("b", "Bool");
		assert("i", "Null<Null<Int>>");
		assert("s", "String");
		assert("d", "Dynamic");
		assert("n", "Null");
		assert("t", "True");
		assert("f", "False");
		assert("unknown", null);
		assert("c", "C<Int,String>");
		assert("unknown", "<Int,String>");
		assert("struct", "{}");
		assert("struct", "{ i : Int }");
		assert("t", "method.T");
		assert("event", "foo.bar.SomeEvent");
		assert("_", "Void");
		assert("_", "Null<Void>");
	}

	function testAddNamesToSignatureType() {
		function assert(expected, original, ?posInfos)
			Assert.equals(expected, addNamesToSignatureType(original), posInfos);

		function assertUnchanged(expectedAndOriginal:Any, ?posInfos)
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
		final letterOverflow = '(${[for (_ in 0...30) ":Int"].join(", ")}):Void';
		final fixedSignature = addNamesToSignatureType(letterOverflow);
		Assert.isFalse(fixedSignature.contains("{:")); // { comes after z in ascii
		Assert.equals(2, fixedSignature.split(" b:").length); // arg names must be unique
	}
}

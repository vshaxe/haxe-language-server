package haxeLanguageServer.helper;

using haxeLanguageServer.helper.ArrayHelper;

class ArrayHelperTest extends TestCaseBase {
    function testEquals() {
        assertTrue([].equals([]));
        assertTrue([1].equals([1]));

        assertFalse([1, 2].equals([2, 1]));
        assertFalse([1].equals([1, 1]));
    }

    function testOccurences() {
        assertEquals(0, [].occurences("foo"));
        assertEquals(1, ["foo"].occurences("foo"));
        assertEquals(2, ["bar", "foo", "bar", "bar", "foo"].occurences("foo"));
    }
}
package haxeLanguageServer.helper;

class ArrayHelperTest extends TestCaseBase {
	function testEquals() {
		assertTrue([].equals([]));
		assertTrue([1].equals([1]));

		assertFalse([1, 2].equals([2, 1]));
		assertFalse([1].equals([1, 1]));
	}

	function testOccurrences() {
		assertEquals(0, [].occurrences("foo"));
		assertEquals(1, ["foo"].occurrences("foo"));
		assertEquals(2, ["bar", "foo", "bar", "bar", "foo"].occurrences("foo"));
	}
}

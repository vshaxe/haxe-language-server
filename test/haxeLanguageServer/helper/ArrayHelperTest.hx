package haxeLanguageServer.helper;

class ArrayHelperTest extends Test {
	function testEquals() {
		Assert.isTrue([].equals([]));
		Assert.isTrue([1].equals([1]));

		Assert.isFalse([1, 2].equals([2, 1]));
		Assert.isFalse([1].equals([1, 1]));
	}

	function testOccurrences() {
		Assert.equals(0, [].occurrences("foo"));
		Assert.equals(1, ["foo"].occurrences("foo"));
		Assert.equals(2, ["bar", "foo", "bar", "bar", "foo"].occurrences("foo"));
	}
}

package haxeLanguageServer.helper;

class RangeHelperTest extends TestCaseBase {
	function testRangeIsEmpty() {
		function check(l1, c1, l2, c2)
			return {start: {line: l1, character: c1}, end: {line: l2, character: c2}}.isEmpty();
		assertTrue(check(0, 10, 0, 10));
		assertFalse(check(1, 5, 5, 1));
	}
}

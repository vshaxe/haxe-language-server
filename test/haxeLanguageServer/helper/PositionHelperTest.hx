package haxeLanguageServer.helper;

class PositionHelperTest extends Test {
	function testPositionsEqual() {
		function check(l1, c1, l2, c2)
			return {line: l1, character: c1}.isEqual({line: l2, character: c2});
		Assert.isTrue(check(0, 10, 0, 10));
		Assert.isFalse(check(1, 5, 5, 1));
	}
}

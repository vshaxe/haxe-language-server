package haxeLanguageServer.helper;

using haxeLanguageServer.helper.PositionHelper;

class PositionHelperTest extends TestCaseBase {
    function testPositionsEqual() {
        function check(l1, c1, l2, c2)
            return {line: l1, character: c1 }.isEqual({ line: l2, character: c2 });
        assertTrue(check(0, 10, 0, 10));
        assertFalse(check(1, 5, 5, 1));
    }
}
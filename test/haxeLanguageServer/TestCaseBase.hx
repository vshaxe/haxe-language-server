package haxeLanguageServer;

class TestCaseBase extends haxe.unit.TestCase {
	inline function fail(?pos:haxe.PosInfos) {
		assertTrue(false, pos);
	}
}
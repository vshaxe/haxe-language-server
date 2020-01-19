package haxeLanguageServer.helper;

class SemVerTest extends Test {
	function spec() {
		SemVer.parse("3.4.7") == new SemVer(3, 4, 7);
		SemVer.parse("4.0.0 (git build master @ 2344f233a)") == new SemVer(4, 0, 0);

		SemVer.parse("4.0.0-rc.1+1fdd3d59b") == new SemVer(4, 0, 0);
		SemVer.parse("4.0.0-rc.1+1fdd3d59b").pre == "rc.1";
		SemVer.parse("4.0.0-rc.1+1fdd3d59b").build == "1fdd3d59b";

		SemVer.parse("4.0.0+ef18b2627e") == new SemVer(4, 0, 0);
		SemVer.parse("4.0.0+ef18b2627e").pre == null;
		SemVer.parse("4.0.0+ef18b2627e").build == "ef18b2627e";
	}
}

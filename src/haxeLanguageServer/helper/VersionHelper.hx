package haxeLanguageServer.helper;

class VersionHelper {
	public static function toString(v:haxe.display.Protocol.Version) {
		return v.major
			+ "."
			+ v.minor
			+ "."
			+ v.patch
			+ (if (v.pre == null) "" else "-" + v.pre)
			+ (if (v.build == null) "" else "+" + v.build);
	}
}

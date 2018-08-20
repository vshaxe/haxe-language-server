package haxeLanguageServer.helper;

private typedef Version = {
	final major:Int;
	final minor:Int;
	final patch:Int;
}

abstract SemVer(Version) from Version {
	static final reVersion = ~/^(\d+)\.(\d+)\.(\d+)(?:\s.*)?/;

	var major(get, never):Int;

	inline function get_major()
		return this.major;

	var minor(get, never):Int;

	inline function get_minor()
		return this.minor;

	var patch(get, never):Int;

	inline function get_patch()
		return this.patch;

	public static function parse(s:String) {
		if (!reVersion.match(s))
			return null;

		var major = Std.parseInt(reVersion.matched(1));
		var minor = Std.parseInt(reVersion.matched(2));
		var patch = Std.parseInt(reVersion.matched(3));
		return new SemVer(major, minor, patch);
	}

	inline public function new(major, minor, patch) {
		this = {
			major: major,
			minor: minor,
			patch: patch
		};
	}

	@:op(a >= b) function isEqualOrGreaterThan(other:SemVer):Bool {
		return isEqual(other) || isGreaterThan(other);
	}

	@:op(a > b) function isGreaterThan(other:SemVer):Bool {
		return (major > other.major) || (major == other.major && minor > other.minor) || (major == other.major && minor == other.minor && patch > other.patch);
	}

	@:op(a == b) function isEqual(other:SemVer):Bool {
		return major == other.major && minor == other.minor && patch == other.patch;
	}

	function toString() {
		return '$major.$minor.$patch';
	}
}

package haxeLanguageServer.helper;

class StringHelper {
	public static inline function occurrences(s:String, of:String) {
		return s.length - s.replace(of, "").length;
	}

	public static function untilLastDot(s:String) {
		var dotIndex = s.lastIndexOf(".");
		if (dotIndex == -1)
			return s;
		return s.substring(0, dotIndex);
	}

	public static function untilFirstDot(s:String) {
		var dotIndex = s.indexOf(".");
		if (dotIndex == -1)
			return s;
		return s.substring(0, dotIndex);
	}

	public static function afterLastDot(s:String) {
		var dotIndex = s.lastIndexOf(".");
		if (dotIndex == -1)
			return s;
		return s.substr(dotIndex + 1);
	}
}

package haxeLanguageServer.helper;

inline function occurrences(s:String, of:String) {
	return s.length - s.replace(of, "").length;
}

function untilLastDot(s:String) {
	var dotIndex = s.lastIndexOf(".");
	if (dotIndex == -1)
		return s;
	return s.substring(0, dotIndex);
}

function untilFirstDot(s:String) {
	var dotIndex = s.indexOf(".");
	if (dotIndex == -1)
		return s;
	return s.substring(0, dotIndex);
}

function afterLastDot(s:String) {
	var dotIndex = s.lastIndexOf(".");
	if (dotIndex == -1)
		return s;
	return s.substr(dotIndex + 1);
}

function last(s:String):String {
	return s.charAt(s.length - 1);
}

package haxeLanguageServer.extensions;

private final upperCaseDriveRe = ~/^(\/)?([A-Z]:)/;

/** ported from VSCode sources **/
function toUri(path:FsPath):DocumentUri {
	var path = path.toString();
	path = path.replace("\\", "/");
	if (path.fastCodeAt(0) != "/".code)
		path = "/" + path;

	final parts = ["file://"];

	if (upperCaseDriveRe.match(path))
		path = upperCaseDriveRe.matched(1) + upperCaseDriveRe.matched(2).toLowerCase() + upperCaseDriveRe.matchedRight();

	var lastIdx = 0;
	while (true) {
		final idx = path.indexOf("/", lastIdx);
		if (idx == -1) {
			parts.push(urlEncode2(path.substring(lastIdx)));
			break;
		}
		parts.push(urlEncode2(path.substring(lastIdx, idx)));
		parts.push("/");
		lastIdx = idx + 1;
	}
	return new DocumentUri(parts.join(""));
}

private function urlEncode2(s:String):String {
	return ~/[!'()*]/g.map(s.urlEncode(), function(re) {
		return "%" + re.matched(0).fastCodeAt(0).hex();
	});
}

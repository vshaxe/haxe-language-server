package haxeLanguageServer.helper;

private final driveLetterPathRe = ~/^\/[a-zA-Z]:/;
private final uriRe = ~/^(([^:\/?#]+?):)?(\/\/([^\/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?/;

/** ported from VSCode sources **/
function toFsPath(uri:DocumentUri):FsPath {
	if (!uriRe.match(uri.toString()) || uriRe.matched(2) != "file")
		throw 'Invalid uri: $uri';

	var path = uriRe.matched(5).urlDecode();
	if (driveLetterPathRe.match(path))
		return new FsPath(path.charAt(1).toLowerCase() + path.substr(2));
	else
		return new FsPath(path);
}

function isFile(uri:DocumentUri):Bool {
	return uri.toString().startsWith("file://");
}

function isUntitled(uri:DocumentUri):Bool {
	return uri.toString().startsWith("untitled:");
}

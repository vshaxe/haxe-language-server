package haxeLanguageServer;

using StringTools;

// these was ported from VS Code sources
class Uri {
    public static function fsPathToUri(path:String):String {
        path = path.replace("\\", "/");
        if (path.fastCodeAt(0) != "/".code)
            path = "/" + path;

        var parts = ["file://"];

        if (upperCaseDriveRe.match(path))
            path = upperCaseDriveRe.matched(1) + upperCaseDriveRe.matched(2).toLowerCase() + upperCaseDriveRe.matchedRight();

        var lastIdx = 0;
        while (true) {
            var idx = path.indexOf("/", lastIdx);
            if (idx == -1) {
                parts.push(path.substring(lastIdx).urlEncode());
                break;
            }
            parts.push(path.substring(lastIdx, idx).urlEncode());
            parts.push("/");
            lastIdx = idx + 1;
        }

        return parts.join("");
    }

    public static function uriToFsPath(uri:String):String {
        if (!uriRe.match(uri) || uriRe.matched(2) != "file")
            throw 'Invalid uri: $uri';

        var path = uriRe.matched(5).urlDecode();
        if (driveLetterPathRe.match(path))
            return path.charAt(1).toLowerCase() + path.substr(2);
        else
            return path;
    }

    static var driveLetterPathRe = ~/^\/[a-zA-Z]:/;
    static var upperCaseDriveRe = ~/^(\/)?([A-Z]:)/;
    static var uriRe = ~/^(([^:\/?#]+?):)?(\/\/([^\/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?/;
}

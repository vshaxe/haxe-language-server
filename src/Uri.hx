using StringTools;

// functions here are currently quickly ported from vscode,
// are very ugly and work only on JS.
// TODO: write proper path<->uri conversion functions
class Uri {
    public static function fsPathToUri(path:String):String {
        path = path.replace("\\", "/");
        if (path.fastCodeAt(0) != "/".code)
            path = "/" + path;

        var parts = ["file://"];

        if (upperCaseDriveRe.match(path))
            path = upperCaseDriveRe.matched(1) + upperCaseDriveRe.matched(2).toLowerCase() + upperCaseDriveRe.matchedRight();

        var lastIdx = 0;
        while(true) {
            var idx = path.indexOf("/", lastIdx);
            if (idx == -1) {
                parts.push(encodeURIComponent2(encodeHashQuestion(path.substring(lastIdx))));
                break;
            }
            parts.push(encodeURIComponent2(encodeHashQuestion(path.substring(lastIdx, idx))));
            parts.push("/");
            lastIdx = idx + 1;
        }

        return parts.join("");
    }

    public static function uriToFsPath(uri:String):String {
        if (!uriRe.match(uri))
            throw 'Invalid uri: $uri';

        inline function m(i) {
            var m = uriRe.matched(i);
            return if (m != null) m else "";
        }
        var scheme = m(2);
        var authority = decodeURIComponent(m(4));
        var path = decodeURIComponent(m(5));
        var query = decodeURIComponent(m(7));
        var fragment = decodeURIComponent(m(9));

        if (authority.length > 0 && scheme == 'file')
            return '//$authority$path';
        else if (driveLetterPathRe.match(path))
            return path.charAt(1).toLowerCase() + path.substr(2);
        else
            return path;
    }

    static var driveLetterPathRe = ~/^\/[a-zA-z]:/;
    static var upperCaseDriveRe = ~/^(\/)?([A-Z]:)/;
    static var uriRe = ~/^(([^:\/?#]+?):)?(\/\/([^\/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?/;

    @:extern static inline function decodeURIComponent(s:String):String {
        return untyped __js__("decodeURIComponent({0})", s);
    }

    static function encodeURIComponent2(str:String):String {
        // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/encodeURIComponent
        return untyped __js__("encodeURIComponent({0}).replace(/[!'()*]/g, {1})", str, _encode);
    }

    static inline function encodeHashQuestion(s:String):String {
        return untyped __js__("{0}.replace(/[#?]/, {1})", s, _encode);
    }

    static function _encode(ch:String):String {
        return untyped __js__("'%' + {0}.charCodeAt(0).toString(16).toUpperCase()", ch);
    }
}

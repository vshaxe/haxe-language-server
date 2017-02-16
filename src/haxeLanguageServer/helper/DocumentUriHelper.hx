package haxeLanguageServer.helper;

class DocumentUriHelper {
    static var driveLetterPathRe = ~/^\/[a-zA-Z]:/;
    static var uriRe = ~/^(([^:\/?#]+?):)?(\/\/([^\/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?/;

    /** ported from VSCode sources **/
    public static function toFsPath(uri:DocumentUri):FsPath {
        if (!uriRe.match(uri.toString()) || uriRe.matched(2) != "file")
            throw 'Invalid uri: $uri';

        var path = uriRe.matched(5).urlDecode();
        if (driveLetterPathRe.match(path))
            return new FsPath(path.charAt(1).toLowerCase() + path.substr(2));
        else
            return new FsPath(path);
    }
}


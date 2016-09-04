package haxeLanguageServer.helper;

import haxe.io.Path;
using StringTools;

class PathHelper {
    public static function matches(path:String, pathFilter:String):Bool {
        return new EReg(pathFilter, "").match(PathHelper.normalize(path));
    }
    public static function preparePathFilter(diagnosticsPathFilter:String, haxelibPath:String, workspacePath:String):String {
        var path = diagnosticsPathFilter;
        path = path.replace("${workspacePath}", workspacePath);
        if (haxelibPath != null) {
            path = path.replace("${haxelibPath}", haxelibPath);
        } else {
            // This doesn't really belong here...
            trace("Could not retrieve haxelib repo path for diagnostics filtering");
        }
        return normalize(path);
    }

    static var reUpperCaseDriveLetter = ~/^([A-Z]:)/;

    public static function normalize(path:String):String {
        path = Path.normalize(path);
        // we need to make sure the case of the drive letter doesn't matter (C: vs c:)
        if (reUpperCaseDriveLetter.match(path)) {
            var letter = path.substr(0, 1).toLowerCase();
            path = letter + path.substring(1);
        }
        return path;
    }
}
package haxeLanguageServer.helper;

import haxe.io.Path;

class PathHelper {
    public static function matches(path:FsPath, pathFilter:FsPath):Bool {
        return new EReg(pathFilter.toString(), "").match(PathHelper.normalize(path).toString());
    }

    public static function preparePathFilter(diagnosticsPathFilter:String, haxelibPath:FsPath, workspaceRoot:FsPath):FsPath {
        var path = diagnosticsPathFilter;
        path = path.replace("${workspaceRoot}", workspaceRoot.toString());
        if (haxelibPath != null)
            path = path.replace("${haxelibPath}", haxelibPath.toString());
        return normalize(new FsPath(path));
    }

    static var reUpperCaseDriveLetter = ~/^([A-Z]:)/;

    public static function normalize(path:FsPath):FsPath {
        var strPath = Path.normalize(path.toString());
        // we need to make sure the case of the drive letter doesn't matter (C: vs c:)
        if (reUpperCaseDriveLetter.match(strPath)) {
            var letter = strPath.substr(0, 1).toLowerCase();
            strPath = letter + strPath.substring(1);
        }
        return new FsPath(strPath);
    }
}
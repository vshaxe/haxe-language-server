class FsUtils {
    static var properFileNameCaseCache:Map<String,String>;
    static var isWindows = Sys.systemName() == "Windows";

    public static function getProperFileNameCase(normalizedPath:String):String {
        if (!isWindows) return normalizedPath;
        if (properFileNameCaseCache == null) {
            properFileNameCaseCache = new Map();
        } else {
            var cached = properFileNameCaseCache[normalizedPath];
            if (cached != null)
                return cached;
        }
        var result = normalizedPath;
        var idx = normalizedPath.lastIndexOf("\\");
        if (idx != -1) {
            var dir = normalizedPath.substring(0, idx);
            var file = normalizedPath.substring(idx + 1);
            for (realFile in sys.FileSystem.readDirectory(dir)) {
                if (realFile.toLowerCase() == file) {
                    result = dir + "\\" + realFile;
                    break;
                }
            }
        }
        return properFileNameCaseCache[normalizedPath] = result;
    }
}

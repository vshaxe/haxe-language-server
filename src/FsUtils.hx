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
        var parts = normalizedPath.split("\\");
        if (parts.length > 1) {
            var acc = parts[0];
            for (i in 1...parts.length) {
                var part = parts[i];
                for (realFile in sys.FileSystem.readDirectory(acc)) {
                    if (realFile.toLowerCase() == part) {
                        part = realFile;
                        break;
                    }
                }
                acc = acc + "/" + part;
            }
            result = acc;
        }
        return properFileNameCaseCache[normalizedPath] = result;
    }
}

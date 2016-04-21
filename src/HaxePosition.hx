@:forward
abstract HaxePosition(HaxePositionData) from HaxePositionData to HaxePositionData {
    static var positionRe = ~/^(.+):(\d+): (?:lines (\d+)-(\d+)|character(?:s (\d+)-| )(\d+))$/;
    static var properFileNameCaseCache:Map<String,String>;
    static var isWindows = (Sys.systemName() == "Windows");

    public static function parse(pos:String):Null<HaxePosition> {
        return if (positionRe.match(pos))
            {
                file: getProperFileNameCase(positionRe.matched(1)),
                line: Std.parseInt(positionRe.matched(2)),
                startLine: Std.parseInt(positionRe.matched(3)),
                endLine: Std.parseInt(positionRe.matched(4)),
                startByte: Std.parseInt(positionRe.matched(5)),
                endByte: Std.parseInt(positionRe.matched(6)),
            }
        else
            null;
    }

    static function getProperFileNameCase(normalizedPath:String):String {
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

typedef HaxePositionData = {
    file:String,
    line:Int, // 1-based
    startLine:Null<Int>, // 1-based
    endLine:Null<Int>, // 1-based
    startByte:Null<Int>, // 0-based byte offset
    endByte:Null<Int>, // 0-based byte offset
}

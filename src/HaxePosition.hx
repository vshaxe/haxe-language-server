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

    public function toRange(stdinDoc:TextDocument, cache:Map<String,Array<String>>):vscode.BasicTypes.Range {
        var pos = this;
        var startLine = if (pos.startLine != null) pos.startLine - 1 else pos.line - 1;
        var endLine = if (pos.endLine != null) pos.endLine - 1 else pos.line - 1;
        var startChar = 0;
        var endChar = 0;

        // if we have byte offsets within line, we need to convert them to character offsets
        // for that we have to read the file :-/
        var lines = null;
        var isStdinDoc = (stdinDoc.fsPath == pos.file);

        inline function getLineChar(line:Int, byteOffset:Int):Int {

            inline function byteOffsetToCharacterOffset(line:String):Int {
                var buffer = new js.node.Buffer(line, "utf-8");
                var textSlice = buffer.toString("utf-8", 0, byteOffset);
                return textSlice.length;
            }

            var line =
                if (isStdinDoc) {
                    // this is an stdin position - get line from in-memory document
                    stdinDoc.lineAt(line);
                } else {
                    // this is a non-stdin document - get line from on-disk document,
                    // cache lines so we don't have to get it multiple times
                    if (lines == null) {
                        if (cache == null) {
                            lines = sys.io.File.getContent(pos.file).split("\n");
                        } else {
                            lines = cache[pos.file];
                            if (lines == null)
                                lines = cache[pos.file] = sys.io.File.getContent(pos.file).split("\n");
                        }
                    }
                    lines[line];
                }

            return byteOffsetToCharacterOffset(line);
        }

        if (pos.startByte != null && pos.startByte != 0)
            startChar = getLineChar(startLine, pos.startByte);

        if (pos.endByte != null && pos.endByte != 0)
            endChar = getLineChar(endLine, pos.endByte);

        return {
            start: {line: startLine, character: startChar},
            end: {line: endLine, character: endChar},
        };
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

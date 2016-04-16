@:forward
abstract HaxePosition(HaxePositionData) from HaxePositionData to HaxePositionData {
    static var positionRe = ~/^(.+):(\d+): (?:lines (\d+)-(\d+)|character(?:s (\d+)-| )(\d+))$/;

    public static function parse(pos:String):Null<HaxePosition> {
        return if (positionRe.match(pos))
            {
                file: positionRe.matched(1),
                line: Std.parseInt(positionRe.matched(2)),
                startLine: Std.parseInt(positionRe.matched(3)),
                endLine: Std.parseInt(positionRe.matched(4)),
                startByte: Std.parseInt(positionRe.matched(5)),
                endByte: Std.parseInt(positionRe.matched(6)),
            }
        else
            null;
    }

    public function toRange():vscode.BasicTypes.Range {
        var pos = this;
        var startLine = if (pos.startLine != null) pos.startLine - 1 else pos.line - 1;
        var endLine = if (pos.endLine != null) pos.endLine - 1 else pos.line - 1;
        var startChar = 0;
        var endChar = 0;

        // if we have byte offsets within line, we need to convert them to character offsets
        // for that we have to read the file :-/
        #if haxe_languageserver_no_utf8_char_pos
        if (pos.startByte != null)
            startChar = pos.startByte;
        if (pos.endByte != null)
            endChar = pos.endByte;
        #else
        var lines = null;
        inline function getLineChar(line:Int, byteOffset:Int):Int {
            if (lines == null) lines = sys.io.File.getContent(pos.file).split("\n");
            var lineContent = new js.node.Buffer(lines[line], "utf-8");
            var lineTextSlice = lineContent.toString("utf-8", 0, byteOffset);
            return lineTextSlice.length;
        }
        if (pos.startByte != null && pos.startByte != 0)
            startChar = getLineChar(startLine, pos.startByte);
        if (pos.endByte != null && pos.endByte != 0)
            endChar = getLineChar(endLine, pos.endByte);
        #end

        return {
            start: {line: startLine, character: startChar},
            end: {line: endLine, character: endChar},
        };
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

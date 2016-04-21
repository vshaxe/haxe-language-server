@:forward
abstract HaxePosition(HaxePositionData) from HaxePositionData to HaxePositionData {
    static var positionRe = ~/^(.+):(\d+): (?:lines (\d+)-(\d+)|character(?:s (\d+)-| )(\d+))$/;

    public static function parse(pos:String):Null<HaxePosition> {
        return if (positionRe.match(pos))
            {
                file: FsUtils.getProperFileNameCase(positionRe.matched(1)),
                line: Std.parseInt(positionRe.matched(2)),
                startLine: Std.parseInt(positionRe.matched(3)),
                endLine: Std.parseInt(positionRe.matched(4)),
                startByte: Std.parseInt(positionRe.matched(5)),
                endByte: Std.parseInt(positionRe.matched(6)),
            }
        else
            null;
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

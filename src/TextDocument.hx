import js.node.Buffer;
import vscode.BasicTypes;
import vscode.ProtocolTypes;

class TextDocument {
    public var uri(default,null):String;
    public var languageId(default,null):String;
    public var version(default,null):Int;
    public var content(default,null):String;
    public var lineCount(get,never):Int;
    var lineOffsets:Array<Int>;

    public function new(uri:String, languageId:String, version:Int, content:String) {
        this.uri = uri;
        this.languageId = languageId;
        this.version = version;
        this.content = content;
    }

    public function update(event:TextDocumentContentChangeEvent, version:Int):Void {
        this.version = version;
        content = event.text;
        lineOffsets = null;
    }

    public function positionAt(offset:Int):Position {
        offset = Std.int(Math.max(Math.min(offset, content.length), 0));

        var lineOffsets = getLineOffsets();
        var low = 0, high = lineOffsets.length;
        if (high == 0)
            return {line: 0, character: offset};
        while (low < high) {
            var mid = Std.int((low + high) / 2);
            if (lineOffsets[mid] > offset)
                high = mid;
            else
                low = mid + 1;
        }
        var line = low - 1;
        return {line: line, character: offset - lineOffsets[line]};
    }

    public function offsetToByteOffset(offset:Int):Int {
        if (offset == 0)
            return 0;
        if (offset == content.length)
            return Buffer.byteLength(content);
        return Buffer.byteLength(content.substr(0, offset));
    }

    public function byteOffsetAt(position:Position):Int {
        return offsetToByteOffset(offsetAt(position));
    }

    public function offsetAt(position:Position):Int {
        var lineOffsets = getLineOffsets();
        if (position.line >= lineOffsets.length)
            return content.length;
        else if (position.line < 0)
            return 0;
        var lineOffset = lineOffsets[position.line];
        var nextLineOffset = (position.line + 1 < lineOffsets.length) ? lineOffsets[position.line + 1] : content.length;
        return Std.int(Math.max(Math.min(lineOffset + position.character, nextLineOffset), lineOffset));
    }

    function getLineOffsets() {
        if (lineOffsets == null) {
            var offsets = [];
            var text = content;
            var isLineStart = true;
            var i = 0;
            while (i < text.length) {
                if (isLineStart) {
                    offsets.push(i);
                    isLineStart = false;
                }
                var ch = text.charCodeAt(i);
                isLineStart = (ch == '\r'.code || ch == '\n'.code);
                if (ch == '\r'.code && i + 1 < text.length && text.charCodeAt(i + 1) == '\n'.code)
                    i++;
                i++;
            }
            if (isLineStart && text.length > 0)
                offsets.push(text.length);
            return lineOffsets = offsets;
        }
        return lineOffsets;
    }

    inline function get_lineCount() return getLineOffsets().length;
}

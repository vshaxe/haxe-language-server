package haxeLanguageServer;

import haxe.io.Bytes;
import byte.ByteData;
import haxe.Timer;
import hxParser.ParseTree;
import haxeparser.HaxeLexer;
import haxeparser.Data;
import tokentree.TokenTreeBuilder;
import tokentree.TokenTree;

typedef OnTextDocumentChangeListener = TextDocument->Array<TextDocumentContentChangeEvent>->Int->Void;

class TextDocument {
    public final uri:DocumentUri;
    public final fsPath:FsPath;
    public final languageId:String;
    public final openTimestamp:Float;
    public var version:Int;
    public var content:String;
    public var lineCount(get,never):Int;
    public var parseTree(get,never):File;
    public var bytes(get,never):Bytes;
    public var tokens(get,never):Array<Token>;
    public var tokenTree(get,never):TokenTree;
    var _parseTree:Null<File>;
    var _bytes:Bytes;
    var _tokens:Array<Token>;
    var _tokenTree:Null<TokenTree>;
    @:allow(haxeLanguageServer.TextDocuments)
    var lineOffsets:Array<Int>;
    var onUpdateListeners:Array<OnTextDocumentChangeListener> = [];

    public function new(uri:DocumentUri, languageId:String, version:Int, content:String) {
        this.uri = uri;
        this.fsPath = uri.toFsPath();
        this.languageId = languageId;
        this.openTimestamp = Timer.stamp();
        this.version = version;
        this.content = content;
    }

    public function update(events:Array<TextDocumentContentChangeEvent>, version:Int):Void {
        for (listener in onUpdateListeners)
            listener(this, events, version);

        this.version = version;
        for (event in events) {
            if (event.range == null || event.rangeLength == null) {
                content = event.text;
            } else {
                var offset = offsetAt(event.range.start);
                var before = content.substring(0, offset);
                var after = content.substring(offset + event.rangeLength);
                content = before + event.text + after;
            }
        }
        _parseTree = null;
        _bytes = null;
        _tokens = null;
        _tokenTree = null;
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

    public inline function byteRangeToRange(byteRange:Range, offsetConverter:DisplayOffsetConverter):Range {
        return {
            start: bytePositionToPosition(byteRange.start, offsetConverter),
            end: bytePositionToPosition(byteRange.end, offsetConverter),
        };
    }

    inline function bytePositionToPosition(bytePosition:Position, offsetConverter:DisplayOffsetConverter):Position {
        var line = lineAt(bytePosition.line);
        return {
            line: bytePosition.line,
            character: offsetConverter.byteOffsetToCharacterOffset(line, bytePosition.character)
        };
    }

    public function lineAt(line:Int):String {
        var lineOffsets = getLineOffsets();
        if (line >= lineOffsets.length)
            return "";
        else if (line == lineOffsets.length - 1)
            return content.substring(lineOffsets[line]);
        else
            return content.substring(lineOffsets[line], lineOffsets[line + 1]);
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

    public function indentAt(line:Int):String {
        var re = ~/^\s*/;
        re.match(lineAt(line));
        return re.matched(0);
    }

    public function getText(range:Range) {
        return content.substring(offsetAt(range.start), offsetAt(range.end));
    }

    public function addUpdateListener(listener:OnTextDocumentChangeListener) {
        onUpdateListeners.push(listener);
    }

    public function removeUpdateListener(listener:OnTextDocumentChangeListener) {
        onUpdateListeners.remove(listener);
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

    function createParseTree() {
        return try switch (hxParser.HxParser.parse(content)) {
            case Success(tree):
                new hxParser.Converter(tree).convertResultToFile();
            case Failure(error):
                trace('hxparser failed to parse $uri with: \'$error\'');
                null;
        } catch (e:Any) {
            trace('hxParser.Converter failed on $uri with: \'$e\'');
            null;
        }
    }

    function get_parseTree() {
        if (_parseTree == null) {
            _parseTree = createParseTree();
        }
        return _parseTree;
    }

    function get_bytes():Bytes {
        if (_bytes == null) {
            _bytes = Bytes.ofString(content);
        }
        return _bytes;
    }

    function createTokens():Array<Token> {
        return try {
            var tokens = [];
            var lexer = new HaxeLexer(ByteData.ofBytes(bytes));
            var t:Token = lexer.token(haxeparser.HaxeLexer.tok);
            while (t.tok != Eof) {
                tokens.push(t);
                t = lexer.token(haxeparser.HaxeLexer.tok);
            }
            tokens;
        } catch (e:Any) {
            trace('failed to create tokens for $uri: $e');
            null;
        }
    }

    function get_tokens():Array<Token> {
        if (_tokens == null) {
            _tokens = createTokens();
        }
        return _tokens;
    }

    function get_tokenTree():TokenTree {
        if (_tokenTree == null) {
            try {
                tokentree.TokenStream.MODE = RELAXED;
                _tokenTree = TokenTreeBuilder.buildTokenTree(createTokens(), ByteData.ofBytes(bytes));
            } catch (e:Any) {
                trace('failed to create token tree for $uri: $e');
            }
        }
        return _tokenTree;
    }
}
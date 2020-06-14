package haxeLanguageServer.documents;

import haxe.Timer;

typedef OnTextDocumentChangeListener = TextDocument->Array<TextDocumentContentChangeEvent>->Int->Void;

class TextDocument {
	public final uri:DocumentUri;
	public final languageId:String;
	public final openTimestamp:Float;
	public var version:Int;
	public var content:String;
	public var lineCount(get, never):Int;

	final context:Null<Context>;

	var lineOffsets:Array<Int>;
	var onUpdateListeners:Array<OnTextDocumentChangeListener> = [];

	public function new(?context:Context, uri:DocumentUri, languageId:String, version:Int, content:String) {
		this.context = context;
		this.uri = uri;
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
			if (event.range == null) {
				content = event.text;
			} else {
				var before = content.substring(0, offsetAt(event.range.start));
				var after = content.substring(offsetAt(event.range.end));
				content = before + event.text + after;
				lineOffsets = null;
			}
		}
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

	public function rangeAt(startOffset:Int, endOffset:Int):Range {
		return {
			start: positionAt(startOffset),
			end: positionAt(endOffset)
		};
	}

	public inline function rangeAt2(pos:haxe.macro.Expr.Position):Range {
		return rangeAt(pos.min, pos.max);
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

	public inline function characterAt(pos:Position) {
		return getText({start: pos, end: pos.translate(0, 1)});
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

	inline function get_lineCount()
		return getLineOffsets().length;
}

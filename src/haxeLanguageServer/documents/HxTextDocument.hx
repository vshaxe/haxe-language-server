package haxeLanguageServer.documents;

import haxe.Timer;

typedef OnTextDocumentChangeListener = HxTextDocument->Array<TextDocumentContentChangeEvent>->Int->Void;

class HxTextDocument {
	public final uri:DocumentUri;
	public final languageId:String;
	public final openTimestamp:Float;
	public var version:Int;
	public var content:String;
	public var lineCount(get, never):Int;

	var lineOffsets:Null<Array<Int>>;
	var onUpdateListeners:Array<OnTextDocumentChangeListener> = [];

	public function new(uri:DocumentUri, languageId:String, version:Int, content:String) {
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
				lineOffsets = null;
			} else {
				final startOffset = offsetAt(event.range.start);
				final endOffset = offsetAt(event.range.end);
				final before = content.substring(0, startOffset);
				final after = content.substring(endOffset);
				content = before + event.text + after;

				// Update offsets
				final startLine = Std.int(Math.max(event.range.start.line, 0));
				final endLine = Std.int(Math.max(event.range.end.line, 0));
				final addedLineOffsets = computeLineOffsets(event.text, false, startOffset);

				if (endLine - startLine == addedLineOffsets.length) {
					for (i in 0...addedLineOffsets.length) {
						lineOffsets.sure()[i + startLine + 1] = addedLineOffsets[i];
					}
				} else {
					lineOffsets = lineOffsets.sure()
						.slice(0, startLine + 1)
						.concat(addedLineOffsets)
						.concat(lineOffsets.sure().slice(endLine + 1));
				}

				final diff = event.text.length - (endOffset - startOffset);
				if (diff != 0) {
					for (i in (startLine + 1 + addedLineOffsets.length)...lineOffsets.sure().length)
						lineOffsets.sure()[i] = lineOffsets.sure()[i] + diff;
				}
			}
		}
	}

	public function positionAt(offset:Int, isUtf8 = false):Position {
		if (isUtf8) {
			offset = utf8Offset(content, offset, 1);
		}
		offset = Std.int(Math.max(Math.min(offset, content.length), 0));

		final lineOffsets = getLineOffsets();
		var low = 0, high = lineOffsets.length;
		if (high == 0)
			return {line: 0, character: offset};
		while (low < high) {
			final mid = Std.int((low + high) / 2);
			if (lineOffsets[mid] > offset)
				high = mid;
			else
				low = mid + 1;
		}
		final line = low - 1;
		return {line: line, character: offset - lineOffsets[line]};
	}

	overload public extern inline function rangeAt(startOffset:Int, endOffset:Int, isUtf8 = false):Range {
		return {
			start: positionAt(startOffset, isUtf8),
			end: positionAt(endOffset, isUtf8)
		};
	}

	overload public extern inline function rangeAt(pos:haxe.macro.Expr.Position, isUtf8 = false):Range {
		return rangeAt(pos.min, pos.max, isUtf8);
	}

	/**
		returns a range instance spanning the line at offset
	**/
	public function lineRangeAt(offsetInLine:Int):Range {
		var start:Position = positionAt(offsetInLine);
		var line:String = lineAt(start.line);
		return {
			start: {
				line: start.line,
				character: 0
			},
			end: {
				line: start.line,
				character: line.rtrim().length
			}
		};
	}

	public function lineAt(line:Int):String {
		final lineOffsets = getLineOffsets();
		if (line >= lineOffsets.length)
			return "";
		else if (line == lineOffsets.length - 1)
			return content.substring(lineOffsets[line]);
		else
			return content.substring(lineOffsets[line], lineOffsets[line + 1]);
	}

	public function offsetAt(position:Position):Int {
		final lineOffsets = getLineOffsets();
		if (position.line >= lineOffsets.length)
			return content.length;
		else if (position.line < 0)
			return 0;
		final lineOffset = lineOffsets[position.line];
		final nextLineOffset = (position.line + 1 < lineOffsets.length) ? lineOffsets[position.line + 1] : content.length;
		return Std.int(Math.max(Math.min(lineOffset + position.character, nextLineOffset), lineOffset));
	}

	public function indentAt(line:Int):String {
		final re = ~/^\s*/;
		re.match(lineAt(line));
		return re.matched(0);
	}

	public function getText(?range:Range) {
		if (range == null) {
			return content;
		}
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

	function getLineOffsets():Array<Int> {
		if (lineOffsets == null) {
			lineOffsets = computeLineOffsets(content, true);
		}
		return lineOffsets;
	}

	function computeLineOffsets(text:String, isLineStart:Bool, offset:Int = 0):Array<Int> {
		final offsets = isLineStart ? [offset] : [];
		var i = 0;
		while (i < text.length) {
			final ch = text.charCodeAt(i);
			if (ch == '\r'.code && i + 1 < text.length && text.charCodeAt(i + 1) == '\n'.code)
				i++;

			i++;
			if (ch == '\r'.code || ch == '\n'.code)
				offsets.push(offset + i);
		}
		return offsets;
	}

	inline function get_lineCount()
		return getLineOffsets().length;

	function utf8Offset(string:String, offset:Int, direction:Int):Int {
		var ret = offset;
		var i = 0, j = 0;
		while (j < string.length && i < offset) {
			var ch = string.charCodeAt(j).sure();
			if (ch >= 0x0000 && ch <= 0x007F) {
				// 1
			} else if (ch >= 0x0080 && ch <= 0x07FF) {
				// 2
				ret -= direction;
			} else if (ch >= 0xD800 && ch < 0xDC00) {
				// surrogate pair
				ret -= direction * 2;
				j++;
			} else if (ch >= 0x0800 && ch <= 0xFFFF) {
				// 3
				ret -= direction * 2;
			} else if (ch >= 0x10000 && ch <= 0x10FFFF) {
				// 4
				ret -= direction * 3;
			} else {} // invalid char
			i++;
			j++;
		}
		return ret;
	}
}

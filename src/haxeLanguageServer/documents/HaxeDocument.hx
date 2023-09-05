package haxeLanguageServer.documents;

import haxeLanguageServer.tokentree.TokenTreeManager;

class HaxeDocument extends HxTextDocument {
	public var tokens(get, never):Null<TokenTreeManager>;

	var _tokens:Null<TokenTreeManager>;

	override function update(events:Array<TextDocumentContentChangeEvent>, version:Int) {
		super.update(events, version);
		_tokens = null;
	}

	public inline function byteRangeToRange(byteRange:Range, offsetConverter:DisplayOffsetConverter):Range {
		return {
			start: bytePositionToPosition(byteRange.start, offsetConverter),
			end: bytePositionToPosition(byteRange.end, offsetConverter),
		};
	}

	inline function bytePositionToPosition(bytePosition:Position, offsetConverter:DisplayOffsetConverter):Position {
		final line = lineAt(bytePosition.line);
		return {
			line: bytePosition.line,
			character: offsetConverter.byteOffsetToCharacterOffset(line, bytePosition.character)
		};
	}

	function get_tokens() {
		if (_tokens == null) {
			try {
				_tokens = TokenTreeManager.create(content);
			} catch (e) {
				// trace('$uri: $e');
			}
		}
		return _tokens;
	}
}

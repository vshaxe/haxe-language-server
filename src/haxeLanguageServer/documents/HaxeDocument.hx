package haxeLanguageServer.documents;

import haxeLanguageServer.tokentree.TokenTreeManager;
import hxParser.ParseTree;

class HaxeDocument extends TextDocument {
	public var parseTree(get, never):Null<File>;
	public var tokens(get, never):Null<TokenTreeManager>;

	var _parseTree:Null<File>;
	var _tokens:Null<TokenTreeManager>;

	override function update(events:Array<TextDocumentContentChangeEvent>, version:Int) {
		super.update(events, version);
		_parseTree = null;
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

	function createParseTree() {
		return try switch hxParser.HxParser.parse(content) {
			case Success(tree):
				new hxParser.Converter(tree).convertResultToFile();
			case Failure(error):
				trace('hxparser failed to parse $uri with: \'$error\'');
				null;
		} catch (e) {
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

	function get_tokens() {
		if (_tokens == null) {
			try {
				_tokens = TokenTreeManager.create(content);
			} catch (e) {
				trace('$uri: $e');
			}
		}
		return _tokens;
	}
}

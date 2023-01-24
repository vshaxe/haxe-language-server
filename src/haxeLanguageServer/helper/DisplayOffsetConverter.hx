package haxeLanguageServer.helper;

import js.node.Buffer;

/**
	This is a helper that provides completion between character and bytes offsets.
	This is required in Haxe 3.x because it uses byte offsets for positions and display queries.
	Haxe 4, however, uses unicode-aware lexer and uses characters for positions, so no
	conversion is required. So we have two implementations, one of which is selected based on
	Haxe version.
**/
abstract class DisplayOffsetConverter {
	public static function create(haxeVersion:SemVer):DisplayOffsetConverter {
		return if (haxeVersion >= new SemVer(4, 0, 0)) new Haxe4DisplayOffsetConverter() else new Haxe3DisplayOffsetConverter();
	}

	public abstract function positionCharToZeroBasedColumn(char:Int):Int;

	public abstract function byteOffsetToCharacterOffset(string:String, byteOffset:Int):Int;

	public abstract function characterOffsetToByteOffset(string:String, offset:Int):Int;
}

class Haxe3DisplayOffsetConverter extends DisplayOffsetConverter {
	public function new() {}

	function positionCharToZeroBasedColumn(char:Int):Int {
		return char;
	}

	function byteOffsetToCharacterOffset(string:String, byteOffset:Int):Int {
		final buf = Buffer.from(string, "utf-8");
		return buf.toString("utf-8", 0, byteOffset).length;
	}

	function characterOffsetToByteOffset(string:String, offset:Int):Int {
		if (offset == 0)
			return 0;
		else if (offset == string.length)
			return Buffer.byteLength(string, "utf-8");
		else
			return Buffer.byteLength(string.substr(0, offset), "utf-8");
	}
}

class Haxe4DisplayOffsetConverter extends DisplayOffsetConverter {
	public function new() {}

	function positionCharToZeroBasedColumn(char:Int):Int {
		return char - 1;
	}

	function byteOffsetToCharacterOffset(string:String, offset:Int):Int {
		return inline offsetSurrogates(string, offset, 1);
	}

	function characterOffsetToByteOffset(string:String, offset:Int):Int {
		return inline offsetSurrogates(string, offset, -1);
	}

	function offsetSurrogates(string:String, offset:Int, direction:Int):Int {
		var ret = offset;
		var i = 0;
		while (i < string.length && i < offset) {
			var ch = string.charCodeAt(i).sure();
			if (ch > 0xD800 && ch < 0xDC00) ret += direction;
			i++;
		}
		return ret;
	}
}

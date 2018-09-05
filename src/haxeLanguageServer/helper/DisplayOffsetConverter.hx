package haxeLanguageServer.helper;

import js.node.Buffer;

/**
	This is a helper that provides completion between character and bytes offsets.
	This is required in Haxe 3.x because it uses byte offsets for positions and display queries.
	Haxe 4, however, uses unicode-aware lexer and uses characters for positions, so no
	conversion is required. So we have two implementations, one of which is selected based on
	Haxe version.
**/
class DisplayOffsetConverter {
	public static function create(haxeVersion:SemVer):DisplayOffsetConverter {
		if (haxeVersion >= new SemVer(4, 0, 0))
			return new Haxe4DisplayOffsetConverter();
		else
			return new Haxe3DisplayOffsetConverter();
	}

	public function positionCharToZeroBasedColumn(char:Int):Int
		throw "abstract method";

	public function byteOffsetToCharacterOffset(string:String, byteOffset:Int):Int
		throw "abstract method";

	public function characterOffsetToByteOffset(string:String, offset:Int):Int
		throw "abstract method";
}

class Haxe3DisplayOffsetConverter extends DisplayOffsetConverter {
	public function new() {}

	override function positionCharToZeroBasedColumn(char:Int):Int {
		return char;
	}

	override function byteOffsetToCharacterOffset(string:String, byteOffset:Int):Int {
		var buf = new js.node.Buffer(string, "utf-8");
		return buf.toString("utf-8", 0, byteOffset).length;
	}

	override function characterOffsetToByteOffset(string:String, offset:Int):Int {
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

	override function positionCharToZeroBasedColumn(char:Int):Int {
		return char - 1;
	}

	override function byteOffsetToCharacterOffset(_, offset:Int):Int {
		return offset;
	}

	override function characterOffsetToByteOffset(_, offset:Int):Int {
		return offset;
	}
}

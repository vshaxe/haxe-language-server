package haxeLanguageServer.helper;

import languageServerProtocol.Types;

class ProtocolTypesHelper {
    public static function isEmpty(r:Range):Bool {
        return r.end.equals(r.start);
    }

    public static function equals(a:Position, b:Position):Bool {
        return a.line == b.line && a.character == b.character;
    }

    public static function translate(pos:Position, lines:Int, characters:Int):Position {
        return {line: pos.line + lines, character: pos.character + characters};
    }

    public static function toRange(pos:Position):Range {
        return {start: pos, end: pos};
    }
}
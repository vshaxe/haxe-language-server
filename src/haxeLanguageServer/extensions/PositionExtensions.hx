package haxeLanguageServer.extensions;

class PositionStatics {
	public static function Min(pos1:Position, pos2:Position) {
		return if (pos1.isBefore(pos2)) pos1 else pos2;
	}

	public static function Max(pos1:Position, pos2:Position) {
		return if (pos1.isAfter(pos2)) pos1 else pos2;
	}
}

/**
 * Extends `languageServerProtocol.Types.Position` with the
 * same utility methods that `vscode.Position` provides
 * (`vscode\src\vs\workbench\api\node\extHostTypes.ts`).
 */
/**
 * Check if `other` is before this position.
 *
 * @param other A position.
 * @return `true` if position is on a smaller line
 * or on the same line on a smaller character.
 */
function isBefore(pos:Position, other:Position):Bool {
	if (pos.line < other.line) {
		return true;
	}
	if (other.line < pos.line) {
		return false;
	}
	return pos.character < other.character;
}

/**
 * Check if `other` is before or equal to this position.
 *
 * @param other A position.
 * @return `true` if position is on a smaller line
 * or on the same line on a smaller or equal character.
 */
function isBeforeOrEqual(pos:Position, other:Position):Bool {
	if (pos.line < other.line) {
		return true;
	}
	if (other.line < pos.line) {
		return false;
	}
	return pos.character <= other.character;
}

/**
 * Check if `other` is after this position.
 *
 * @param other A position.
 * @return `true` if position is on a greater line
 * or on the same line on a greater character.
 */
function isAfter(pos:Position, other:Position):Bool {
	return !pos.isBeforeOrEqual(other);
}

/**
 * Check if `other` is after or equal to this position.
 *
 * @param other A position.
 * @return `true` if position is on a greater line
 * or on the same line on a greater or equal character.
 */
function isAfterOrEqual(pos:Position, other:Position):Bool {
	return !pos.isBefore(other);
}

/**
 * Check if `other` equals this position.
 *
 * @param other A position.
 * @return `true` if the line and character of the given position are equal to
 * the line and character of this position.
 */
function isEqual(pos:Position, other:Position):Bool {
	return pos.line == other.line && pos.character == other.character;
}

/**
 * Compare this to `other`.
 *
 * @param other A position.
 * @return A number smaller than zero if this position is before the given position,
 * a number greater than zero if this position is after the given position, or zero when
 * this and the given position are equal.
 */
function compareTo(pos:Position, other:Position):Int {
	if (pos.line < other.line) {
		return -1;
	} else if (pos.line > other.line) {
		return 1;
	} else {
		// equal line
		if (pos.character < other.character) {
			return -1;
		} else if (pos.character > other.character) {
			return 1;
		} else {
			// equal line and character
			return 0;
		}
	}
}

/**
 * Create a new position relative to this position.
 *
 * @param lineDelta Delta value for the line value, default is `0`.
 * @param characterDelta Delta value for the character value, default is `0`.
 * @return A position which line and character is the sum of the current line and
 * character and the corresponding deltas.
 */
inline function translate(pos:Position, lineDelta:Int, characterDelta:Int):Position {
	return {line: pos.line + lineDelta, character: pos.character + characterDelta};
}

/**
 * Derived a new position relative to this position.
 *
 * @param change An object that describes a delta to this position.
 * @return A position that reflects the given delta. Will return `this` position if the change
 * is not changing anything.
 */
inline function translatePos(pos:Position, other:Position):Position {
	return translate(pos, other.line, other.character);
}

/**
 * Create a new position derived from this position.
 *
 * @param line Value that should be used as line value, default is the [existing value](#Position.line)
 * @param character Value that should be used as character value, default is the [existing value](#Position.character)
 * @return A position where line and character are replaced by the given values.
 */
inline function with(pos:Position, ?line:Int, ?character:Int):Position {
	final line:Int = if (line == null) pos.line else line;
	final character:Int = if (character == null) pos.character else character;
	return {line: line, character: character};
}

inline function toRange(pos:Position):Range {
	return {start: pos, end: pos};
}

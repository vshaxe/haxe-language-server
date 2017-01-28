package haxeLanguageServer.helper;

/** 
 * Extends `languageServerProtocol.Types.Range` with the
 * same utility methods that `vscode.Range` provides
 * (`vscode\src\vs\workbench\api\node\extHostTypes.ts`).
 */
class RangeHelper {
    /**
     * `true` if `start` and `end` are equal.
     */
    public static function isEmpty(range:Range):Bool {
        return range.end.isEqual(range.start);
    }

    /**
     * `true` if `start.line` and `end.line` are equal.
     */
    public static function isSingleLine(range:Range):Bool {
        return range.start.line == range.end.line;
    }

    /**
     * Check if a range is contained in this range.
     *
     * @param other A range.
     * @return `true` if the range is inside or equal
     * to this range.
     */
    public static inline function contains(range:Range, other:Range):Bool {
        return range.containsPos(other.start) && range.containsPos(other.end);
    }

    /**
     * Check if a position is contained in this range.
     *
     * @param pos A position.
     * @return `true` if the position is inside or equal
     * to this range.
     */
    public static function containsPos(range:Range, pos:Position):Bool {
        if (pos.isBefore(range.start)) {
            return false;
        }
        if (range.end.isBefore(pos)) {
            return false;
        }
        return true;
    }

    /**
     * Intersect `range` with this range and returns a new range or `undefined`
     * if the ranges have no overlap.
     *
     * @param range A range.
     * @return A range of the greater start and smaller end positions. Will
     * return undefined when there is no overlap.
     */
    public static function intersection(range:Range, other:Range):Range {
        var start = PositionStatics.Max(other.start, range.start);
        var end = PositionStatics.Min(other.end, range.end);
        if (start.isAfter(end)) {
            // this happens when there is no overlap:
            // |-----|
            //          |----|
            return null;
        }
        return {start: start, end: end};
    }

    /**
     * Compute the union of `other` with this range.
     *
     * @param other A range.
     * @return A range of smaller start position and the greater end position.
     */
    public static function union(range:Range, other:Range):Range {
        if (range.contains(other)) {
            return range;
        } else if (other.contains(range)) {
            return other;
        }
        var start = PositionStatics.Min(other.start, range.start);
        var end = PositionStatics.Max(other.end, range.end);
        return {start: start, end: end};
    }

    /**
     * Derived a new range from this range.
     *
     * @param start A position that should be used as start. The default value is the [current start](#Range.start).
     * @param end A position that should be used as end. The default value is the [current end](#Range.end).
     * @return A range derived from this range with the given start and end position.
     * If start and end are not different `this` range will be returned.
     */
    public static function with(range:Range, ?start:Position, ?end:Position):Range {
        var start = if (start == null) range.start else start;
        var end = if (end == null) range.end else end;
        
        if (start.isEqual(range.start) && end.isEqual(range.end)) {
            return range;
        }
        return {start: start, end: end};
    }
}
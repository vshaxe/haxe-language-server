package haxeLanguageServer.helper;

class ArrayHelper {
    public static function occurrences<T>(a:Array<T>, element:T):Int {
        var occurrences = 0;
        for (e in a)
            if (e == element)
                occurrences++;
        return occurrences;
    }

    public static function equals<T>(a1:Array<T>, a2:Array<T>):Bool {
        if (a1 == null && a2 == null) return true;
        if (a1 == null && a2 != null) return false;
        if (a1 != null && a2 == null) return false;
        if (a1.length != a2.length) return false;
        for (i in 0...a1.length)
            if (a1[i] != a2[i])
                return false;
        return true;
    }
}
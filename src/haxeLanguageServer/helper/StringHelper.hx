package haxeLanguageServer.helper;

class StringHelper {
    public static inline function occurrences(s:String, of:String) {
        return s.length - s.replace(of, "").length;
    }
}
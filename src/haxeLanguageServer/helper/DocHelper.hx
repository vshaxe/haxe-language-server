package haxeLanguageServer.helper;

class DocHelper {
    public static function extractText(doc:String):String {
        if (doc == null)
            return null;

        return doc.trim().split("\n").map(function(line) {
            line = line.trim();
            if (line.startsWith("*")) // JavaDoc-style comments
                line = line.substr(1);
            return line;
        }).join("\n");
    }

    public static function formatText(text:String):String {
        if (text == null)
            return null;
        return "/**\n" + text.split("\n").map(function(line) return "\t" + line).join("\n") + "\n**/";
    }
}
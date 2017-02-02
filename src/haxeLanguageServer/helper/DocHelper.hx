package haxeLanguageServer.helper;

class DocHelper {
    /** Stolen from dox **/
    public static function trim(doc:String) {
        if (doc == null)
            return '';

        // trim leading asterisks
        while (doc.charAt(0) == '*')
            doc = doc.substr(1);

        // trim trailing asterisks
        while (doc.charAt(doc.length - 1) == '*')
            doc = doc.substr(0, doc.length - 1);

        // trim additional whitespace
        doc = doc.trim();

        // detect doc comment style/indent
        var ereg = ~/^([ \t]+(\* )?)[^\s\*]/m;
        var matched = ereg.match(doc);

        if (matched) {
            var string = ereg.matched(1);

            // escape asterisk and allow one optional space after it
            string = string.split('* ').join('\\* ?');

            var indent = new EReg("^" + string, "gm");
            doc = indent.replace(doc, "");
        }

        // TODO: check why this is necessary (dox doesn't seem to need it...)
        if (doc.charAt(0) == '*')
            doc = doc.substr(1).ltrim();

        return doc;
    }

    public static function markdownFormat(doc:String):String {
        function tableLine(a, b) return '| $a | $b |\n';
        function tableHeader(a, b) return "\n" + tableLine(a, b) + tableLine("------", "------");
        function replaceNewlines(s:String, by:String) return s.replace("\n", by).replace("\r", by);
        function mapDocTags(tags) return tags.map(function(p) {
            var desc = replaceNewlines(p.doc, " ");
            return tableLine("`" + p.value + "`", desc); }
        ).join("");

        doc = trim(doc);
        var docInfos = JavadocHelper.parse(doc);
        var result = docInfos.doc;
        var hasParams = docInfos.params.length > 0;
        var hasReturn = docInfos.returns != null;
        
        if (docInfos.deprecated != null)
            result += "\n**Deprecated:** " + docInfos.deprecated.doc + "\n";

        if (hasParams || hasReturn)
            result += tableHeader("Argument", "Description");
        if (hasParams)
            result += mapDocTags(docInfos.params);
        if (hasReturn)
            result += tableLine("`return`", replaceNewlines(docInfos.returns.doc, " "));

        if (docInfos.throws.length > 0)
            result += tableHeader("Exception", "Description") + mapDocTags(docInfos.throws);
        
        if (docInfos.sees.length > 0)
            result += "\nSee also:\n" + docInfos.sees.map(function(p) return "* " + p.doc).join("\n") + "\n";

        if (docInfos.since != null)
            result += '\n_Available since ${docInfos.since.doc}_';

        return result;
    }

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
}
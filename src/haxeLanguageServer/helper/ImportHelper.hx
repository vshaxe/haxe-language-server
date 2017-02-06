package haxeLanguageServer.helper;

import haxeLanguageServer.TextDocument;

class ImportHelper {
    static var rePackageDecl = ~/package\s*( [\w\.]*)?\s*;/;

    /**
        Gets the first non-empty line (excluding the package declaration if present),
        which is where we want to insert imports.
     */
    public static function getImportInsertPosition(doc:TextDocument):Position {
        var importLine = skipComment(doc);
        for (i in importLine...doc.lineCount) {
            var line = doc.lineAt(i);
            var isPackageDecl = rePackageDecl.match(line);
            var isNotEmpty = line.trim().length > 0;
            if (!isPackageDecl && isNotEmpty) {
                importLine = i;
                break;
            }
        }
        return { line: importLine, character: 0 };
    }

    /**
        Finds the first line number in a document that is non-empty and
        not within a comment.
     */
    public static function skipComment(doc:TextDocument):Int {
        var retLine = 0;
        var bInComment = false;
        for (i in 0...doc.lineCount) {
            var line = doc.lineAt(i).trim();
            if (line.length == 0 || line.startsWith("//"))
                continue;

            if (line.startsWith("/*"))
                bInComment = true;

            if (bInComment && line.endsWith("*/")) {
                bInComment = false;
                continue;
            }

            if (!bInComment) {
                retLine = i;
                break;
            }
        }
        return retLine;
    }
}

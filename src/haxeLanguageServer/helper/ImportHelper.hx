package haxeLanguageServer.helper;

import haxeLanguageServer.TextDocument;

class ImportHelper {
    static var rePackageDecl = ~/package\s*( [\w\.]*)?\s*;/;
    static var reTypeDecl = ~/^\s*(class|interface|enum|abstract|typedef)/;

    /**
        Creates an import on the first non-empty line (excluding the package declaration if present),
        which is where we want to insert imports.
    **/
    public static function createImport(doc:TextDocument, type:String):TextEdit {
        var importLine = skipComment(doc);
        for (i in importLine...doc.lineCount) {
            var line = doc.lineAt(i);
            var isPackageDecl = rePackageDecl.match(line);
            var isNotEmpty = line.trim().length > 0;
            trace(isPackageDecl, isNotEmpty);
            if (!isPackageDecl && isNotEmpty) {
                importLine = i;
                break;
            }
        }

        var importData = {
            range: {line: importLine, character: 0}.toRange(),
            newText: 'import $type;\n'
        };

        var nextLine = doc.lineAt(importLine);
        var followedByTypeDecl = nextLine != null && reTypeDecl.match(nextLine);
        if (followedByTypeDecl) {
            importData.newText += "\n";
        }

        return importData;
    }

    /**
        Finds the first line number in a document that is non-empty and
        not within a comment.
    **/
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

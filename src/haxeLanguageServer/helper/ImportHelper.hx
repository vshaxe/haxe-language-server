package haxeLanguageServer.helper;

import haxeLanguageServer.TextDocument;
import languageServerProtocol.Types;

class ImportHelper {
    static var rePackageDecl = ~/package\s*( [\w\.]*)?\s*;/;

    /**
        Gets the first non-empty line (excluding the package declaration if present),
        which is where we want to insert imports.
     */
    public static function getImportInsertPosition(doc:TextDocument):Position {
        var importLine = 0;
        for (i in 0...doc.lineCount) {
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
}
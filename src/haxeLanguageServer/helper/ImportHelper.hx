package haxeLanguageServer.helper;

import haxeLanguageServer.TextDocument;

enum abstract ImportStyle(String) {
    var Module = "module";
    var Type = "type";
}

class ImportHelper {
    static final rePackageDecl = ~/package\s*( [\w\.]*)?\s*;/;
    static final reTypeDecl = ~/^\s*(class|interface|enum|abstract|typedef)/;

    public static function createImportEdit(doc:TextDocument, position:Position, paths:Array<String>, style:ImportStyle):TextEdit {
        if (style == Module) {
            paths = paths.map(TypeHelper.getModule);
        }
        var importData = {
            range: position.toRange(),
            newText: paths.map(path -> 'import $path;\n').join("")
        };

        var nextLine = doc.lineAt(position.line);
        var followedByTypeDecl = nextLine != null && reTypeDecl.match(nextLine);
        if (followedByTypeDecl) {
            importData.newText += "\n";
        }

        return importData;
    }

    /**
        Finds the the first non-empty line (excluding the package declaration if present),
        which is where we want to insert imports.
    **/
    public static function getImportPosition(doc:TextDocument):Position {
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
        return {line: importLine, character: 0};
    }
}

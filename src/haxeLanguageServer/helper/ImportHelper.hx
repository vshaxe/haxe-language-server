package haxeLanguageServer.helper;

import haxe.Json;
import haxe.display.JsonModuleTypes;
import haxeLanguageServer.protocol.helper.DisplayPrinter;
import haxeLanguageServer.TextDocument;
using Lambda;

enum abstract ImportStyle(String) {
    var Module = "module";
    var Type = "type";
}

class ImportHelper {
    static final rePackageDecl = ~/package\s*( [\w\.]*)?\s*;/;
    static final reTypeDecl = ~/^\s*(class|interface|enum|abstract|typedef)/;

    public static function createImportsEdit(doc:TextDocument, position:Position, paths:Array<String>, style:ImportStyle):TextEdit {
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

    public static function createFunctionImportsEdit<T>(doc:TextDocument, position:Position, context:Context, type:JsonType<T>, formatting:FunctionFormattingConfig):Array<TextEdit> {
        var importConfig = context.config.codeGeneration.imports;
        if (!importConfig.enableAutoImports) {
            return [];
        }
        var paths = [];
        var signature = type.extractFunctionSignature();
        if (formatting.argumentTypeHints && (!formatting.useArrowSyntax || signature.args.length != 1)) {
            paths = paths.concat(signature.args.map(arg -> arg.t.resolveImports()).flatten().array());
        }
        if (formatting.printReturn(signature)) {
            paths = paths.concat(signature.ret.resolveImports());
        }
        paths = paths.filterDuplicates((e1, e2) -> Json.stringify(e1) == Json.stringify(e2));

        if (paths.length == 0) {
            return [];
        } else {
            var printer = new DisplayPrinter(false, Always);
            return [createImportsEdit(doc, position, paths.map(printer.printPath), importConfig.style)];
        }
    }
}

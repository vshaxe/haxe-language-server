package haxeLanguageServer.helper;

import haxe.unit.TestCase;
import haxeLanguageServer.TextDocument;
import haxe.PosInfos;
using StringTools;

class ImportHelperTest extends TestCase {
    public function testGetImportInsertPosition() {
        function test(file:TestFile, ?pos:PosInfos) {
            var line = -1;
            var lines = (file : String).split("\n");
            for (i in 0...lines.length) {
                // | indicates the desired position
                if (lines[i].indexOf("|") > 0) {
                    line = i;
                    break;
                }
            }
            if (line == -1) {
                throw "test case is missing caret: " + file;
            }

            var doc = new TextDocument("file://dummy", "", 0, file.replace("|", ""));
            var importPos = ImportHelper.getImportInsertPosition(doc);
            assertEquals(0, importPos.character, pos);
            assertEquals(line, importPos.line, pos);
        }

        test(EmptyPackage);
        test(EmptyPackageWithSpaces);
        test(NoPackage);
        test(NoImport);
        test(ComplexPackage);
    }
}

@:enum abstract TestFile(String) to String {
    var EmptyPackage = "
    package;

    |import haxe.io.Path;
    ";

    var EmptyPackageWithSpaces = "
    package   ;

    |import haxe.io.Path;
    ";

    var NoPackage = "


    |import haxe.io.Path;
    ";

    var NoImport = "
    |class SomeClass {
    }
    ";

    var ComplexPackage = "
    
    
    package     test._underscore.____s   ;

    |import haxe.io.Path;
    ";
}
package haxeLanguageServer.helper;

import haxeLanguageServer.TextDocument;
import haxe.PosInfos;

class ImportHelperTest extends Test {
	function testGetImportInsertPosition() {
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

			var doc = new TextDocument(new DocumentUri("file://dummy"), "", 0, file.replace("|", ""));
			var importPos = ImportHelper.getImportPosition(doc);
			Assert.equals(0, importPos.character, pos);
			Assert.equals(line, importPos.line, pos);
		}

		test(EmptyPackage);
		test(EmptyPackageWithSpaces);
		test(NoPackage);
		test(NoImport);
		test(ComplexPackage);
		test(TypeWithDocComment);
	}
}

enum abstract TestFile(String) to String {
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
	var TypeWithDocComment = "
    |/**
        Some doc comment for this type.
    **/
    class Foo {
    ";
}

package haxeLanguageServer.helper;

import haxe.PosInfos;
import haxeLanguageServer.TextDocument;

class ImportHelperTest extends Test {
	function testGetImportInsertPosition() {
		function test(testCase:{before:String, after:String}, ?pos:PosInfos) {
			testCase.before = testCase.before.replace("\r", "");
			testCase.after = testCase.after.replace("\r", "");

			var doc = new TextDocument(new DocumentUri("file://dummy"), "", 0, testCase.before);
			var result = ImportHelper.getImportPosition(doc);
			var edit = ImportHelper.createImportsEdit(doc, result, ["Test"], Type);

			// TODO: apply the edit properly instead of this hack?
			var lines = testCase.before.split("\n");
			var insertLine = edit.range.start.line;
			lines[insertLine] = edit.newText + lines[insertLine];

			Assert.equals(testCase.after, lines.join("\n"), pos);
		}

		// package + import
		test({
			before: "package;

import haxe.io.Path;",

			after: "package;

import Test;
import haxe.io.Path;"
		});

		// package + import with conditional compilation
		test({
			before: "package;

#if false
import haxe.io.Path;
#end",

			after: "package;

import Test;
#if false
import haxe.io.Path;
#end"
		});

		// only import
		test({
			before: "

import haxe.io.Path;",

			after: "

import Test;
import haxe.io.Path;"
		});

		// only type
		test({
			before: "class Foo {
}",
			after: "import Test;

class Foo {
}"
		});

		// type with empty line
		test({
			before: "
class Foo {
}",

			after: "import Test;

class Foo {
}"
		});

		// License header
		test({
			before: "
/**
	License
**/

import Foo;",

			after: "
/**
	License
**/

import Test;
import Foo;"
		});

		// doc comment and license header
		test({
			before: "
/**
	License
**/

/**
	Docs
**/
class Foo",

			after: "
/**
	License
**/

import Test;

/**
	Docs
**/
class Foo"
		});

		// doc comment, line comments and license header
		test({
			before: "
/**
	License
**/

// TODO
// TODO 2
/**
	Docs
**/
class Foo",

			after: "
/**
	License
**/

import Test;

// TODO
// TODO 2
/**
	Docs
**/
class Foo"
		});

		test({
			before: "
package;

@:jsRequire('WebSocket')
extern class WebSocket {}",

			after: "
package;

import Test;

@:jsRequire('WebSocket')
extern class WebSocket {}",

		});

		// issue #414 https://github.com/vshaxe/vshaxe/issues/414
		// first import + meta with comment
		test({
			before: "
package;

@:keep // comment seems to affect this bug
class Main {
    static function main() {
        
    }
}",

			after: "
package;

import Test;

@:keep // comment seems to affect this bug
class Main {
    static function main() {
        
    }
}",

		});
	}
}

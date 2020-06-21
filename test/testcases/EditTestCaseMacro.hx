package testcases;

import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Expr;
import sys.FileSystem;
import sys.io.File;

class EditTestCaseMacro {
	#if macro
	public macro static function build(folder:String):Array<Field> {
		final fields:Array<Field> = Context.getBuildFields();
		final testCases:Array<String> = collectAllFileNames(folder);
		for (testCase in testCases) {
			final field:Field = buildTestCaseField(testCase);
			if (field == null)
				continue;

			fields.push(field);
		}
		return fields;
	}

	static function buildTestCaseField(fileName:String):Field {
		Context.registerModuleDependency(Context.getLocalModule(), fileName);
		final content:String = sys.io.File.getContent(fileName);
		final nl = "\r?\n";
		final reg = new EReg('$nl$nl---$nl$nl', "g");
		final segments = reg.split(content);
		if (segments.length != 3)
			throw 'invalid testcase format for: $fileName';

		final config:String = segments[0];
		final input:String = segments[1];
		final gold:String = segments[2];
		final fileName:String = new haxe.io.Path(fileName).file;
		var fieldName:String = fileName;
		fieldName = "test" + fieldName.charAt(0).toUpperCase() + fieldName.substr(1);

		return (macro class {
			@Test
			public function $fieldName() {
				goldCheck($v{fileName}, $v{input}, $v{gold}, $v{config});
			};
		}).fields[0];
	}

	static function collectAllFileNames(path:String):Array<String> {
		#if display
		return [];
		#end
		final items:Array<String> = FileSystem.readDirectory(path);
		var files:Array<String> = [];
		for (item in items) {
			if (item == "." || item == "..")
				continue;

			final fileName = Path.join([path, item]);
			if (FileSystem.isDirectory(fileName)) {
				files = files.concat(collectAllFileNames(fileName));
				continue;
			}
			if (!item.endsWith(".edittest"))
				continue;

			files.push(Path.join([path, item]));
		}
		return files;
	}
	#end
}

import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.io.Path;
import sys.io.File;
import sys.FileSystem;

class EditTestCaseMacro {
	#if macro
	public macro static function build(folder:String):Array<Field> {
		var fields:Array<Field> = Context.getBuildFields();
		var testCases:Array<String> = collectAllFileNames(folder);
		for (testCase in testCases) {
			var field:Field = buildTestCaseField(testCase);
			if (field == null) {
				continue;
			}
			fields.push(field);
		}
		return fields;
	}

	static function buildTestCaseField(fileName:String):Field {
		var content:String = sys.io.File.getContent(fileName);
		var nl = "\r?\n";
		var reg = new EReg('$nl$nl---$nl$nl', "g");
		var segments = reg.split(content);
		if (segments.length != 3) {
			throw 'invalid testcase format for: $fileName';
		}
		var config:String = segments[0];
		var input:String = segments[1];
		var gold:String = segments[2];
		var fileName:String = new haxe.io.Path(fileName).file;
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
		var items:Array<String> = FileSystem.readDirectory(path);
		var files:Array<String> = [];
		for (item in items) {
			if (item == "." || item == "..") {
				continue;
			}
			var fileName = Path.join([path, item]);
			if (FileSystem.isDirectory(fileName)) {
				files = files.concat(collectAllFileNames(fileName));
				continue;
			}
			if (!item.endsWith(".edittest")) {
				continue;
			}
			files.push(Path.join([path, item]));
		}
		return files;
	}
	#end
}

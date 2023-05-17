import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type.ClassType;

using Lambda;
using StringTools;
using sys.FileSystem;

class BuildMacro {
	#if macro
	static function buildTestCase():Array<Field> {
		var fields = Context.getBuildFields();
		var c = Context.getLocalClass().get();
		for (field in fields) {
			if (field.doc == null) {
				continue;
			}
			var doc = addPackageToDoc(c, field, field.doc);
			doc = StringTools.replace(doc, "**\\/", "**/");
			var transform = Marker.extractMarkers(doc);
			var markers = transform.markers.length > 0 ? macro $a{transform.markers} : macro new Map();
			var filename = Context.getPosInfos(c.pos).file;
			for (meta in field.meta) {
				if (meta.name == ":filename") {
					switch (meta.params[0].expr) {
						case EConst(CString(s)):
							filename = Path.directory(filename) + "/" + s;
						case _:
							throw "String expected";
					}
				}
			}

			final sources = ~/[\s*]---\n/g.split(transform.source);
			sources[0] = sources[0].trim();
			if (sources[1] != null) {
				var doc = addPackageToDoc(c, field, sources[1]);
				doc = StringTools.replace(doc, "**\\/", "**/");
				sources[1] = doc;
			}

			switch (field.kind) {
				case FFun(f) if (f.expr != null):
					f.expr = macro @:pos(f.expr.pos) {
						ctx = new DisplayTestContext($v{filename}, $v{field.name}, $v{sources}, $markers);
						${f.expr}
					};
				case _:
			}
		}

		return fields;
	}

	static function addPackageToDoc(c:ClassType, field:Field, fieldDoc:String):String {
		fieldDoc = fieldDoc.trim();
		var doc = (c.pack.length > 0 ? "package " + c.pack.join(".") + ";\n" : "");
		if (field.meta.exists(function(meta) return meta.name == ":funcCode")) {
			doc += "class Main { static function main() { " + fieldDoc + "}}";
		} else {
			doc += fieldDoc;
		}
		return doc;
	}
	#end

	macro static public function getCases(pack:String) {
		var cases = [];
		var singleCase = haxe.macro.Context.definedValue("test");
		function loop(pack:Array<String>) {
			var path = Context.resolvePath(Path.join(pack));
			for (file in sys.FileSystem.readDirectory(path)) {
				if (singleCase != null && !file.endsWith(singleCase + ".hx")) {
					continue;
				}
				if (file.endsWith("import.hx")) {
					continue;
				}
				var p = new haxe.io.Path(file);
				if (p.ext == "hx") {
					var tp = {pack: pack, name: p.file};
					cases.push(macro new $tp());
				} else if (Path.join([path, file]).isDirectory()) {
					loop(pack.concat([file]));
				}
			}
		}
		loop(pack.split('.'));
		return macro $a{cases};
	}
}

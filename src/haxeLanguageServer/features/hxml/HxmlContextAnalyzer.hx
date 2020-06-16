package haxeLanguageServer.features.hxml;

import haxeLanguageServer.features.hxml.Defines;
import haxeLanguageServer.features.hxml.HxmlFlags;

using Lambda;

function analyzeHxmlContext(line:String, pos:Position):HxmlContext {
	final textBefore = line.substring(0, pos.character);
	final wordPattern = ~/[-\w]+$/;
	final range = {start: pos, end: pos};
	if (wordPattern.match(textBefore)) {
		range.start = pos.translate(0, -wordPattern.matched(0).length);
	}
	final parts = ~/\s+/.replace(textBefore.ltrim(), " ").split(" ");
	function findFlag(word) {
		return HxmlFlags.flatten().find(f -> f.name == word || f.shortName == word || f.deprecatedNames!.contains(word));
	}
	return {
		element: switch parts {
			case []: Flag();
			case [flag]: Flag(findFlag(flag));
			case [flag, arg]:
				final flag = findFlag(flag);
				switch flag!.argument!.kind {
					case null: Unknown;
					case Enum(values): EnumValue(values[arg], values);
					case Define:
						function findDefine(define) {
							return Defines.find(d -> d.define == define);
						}
						switch arg.split("=") {
							case []: Define();
							case [define]: Define(findDefine(define));
							case [define, value]: DefineValue(findDefine(define), value);
							case _: Unknown;
						}
				}
			case _:
				Unknown; // no completion after the first argument
		},
		range: range
	};
}

typedef HxmlContext = {
	final element:HxmlElement;
	final range:Range;
}

enum HxmlElement {
	Flag(?flag:HxmlFlag);
	EnumValue(?value:EnumValue, values:EnumValues);
	Define(?define:Define);
	DefineValue(?define:Define, value:String);
	Unknown;
}

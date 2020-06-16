package haxeLanguageServer.features.hxml;

import haxeLanguageServer.features.hxml.Defines;
import haxeLanguageServer.features.hxml.HxmlFlags;

using Lambda;

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

function analyzeHxmlContext(line:String, pos:Position):HxmlContext {
	final range = findWordRange(line, pos.character);
	final parts = ~/\s+/.replace(line.ltrim(), " ").split(" ");
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
		range: {
			start: {line: pos.line, character: range.start},
			end: {line: pos.line, character: range.end}
		}
	};
}

private function findWordRange(s:String, index:Int) {
	var start = 0;
	var end = s.length - 1;
	var inWord = false;
	for (i in 0...s.length) {
		final c = s.charAt(i);
		if (c.isSpace(0)) {
			if (inWord) {
				inWord = false;
				end = i - 1;
				if (start <= index && end >= index) {
					break;
				}
			}
		} else {
			if (!inWord) {
				inWord = true;
				start = i;
			}
		}
	}
	return {start: start, end: end};
}

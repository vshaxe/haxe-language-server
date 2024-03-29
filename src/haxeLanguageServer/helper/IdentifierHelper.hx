package haxeLanguageServer.helper;

import String.fromCharCode;
import haxeLanguageServer.helper.TypeHelper.DisplayFunctionArgument;

class IdentifierHelper {
	public static function guessNames(args:Array<DisplayFunctionArgument>):Array<String> {
		return avoidDuplicates([for (arg in args) if (arg.name != null) arg.name else guessName(arg.type)]);
	}

	public static function guessName(type:Null<String>):String {
		if (type == null) {
			return "unknown";
		}
		type = TypeHelper.unwrapNullable(type);
		type = TypeHelper.getTypeWithoutParams(type);

		return switch type {
			case "": "unknown";
			case "Int": "i";
			case "Float": "f";
			case "Bool": "b";
			case "String": "s";
			case "Dynamic": "d";
			case "Null": "n";
			case "True": "t";
			case "False": "f";
			case "Void": "_";
			case type if (type.startsWith("{")): "struct";
			case type:
				final segments = ~/(?=[A-Z][^A-Z]*$)/.split(type);
				final result = segments[segments.length - 1];
				result.substring(0, 1).toLowerCase() + result.substr(1);
		}
	}

	public static function avoidDuplicates(names:Array<String>):Array<String> {
		final currentOccurrence:Map<String, Int> = new Map();
		return [
			for (name in names) {
				var i = currentOccurrence[name];
				if (i == null) i = 0;

				if (names.occurrences(name) > 1) i++;
				currentOccurrence[name] = i;

				if (i > 0) name = name + i;
				name;
			}
		];
	}

	/**
		Adds argument names to types from signature completion.

		@param  type   a type like `(:Int, :Int):Void` or `:Int`
		@see https://github.com/HaxeFoundation/haxe/issues/6064
	**/
	public static function addNamesToSignatureType(type:String, index:Int = 0):String {
		inline function getUniqueLetter(index:Int) {
			final letters = 26;
			final alphabets = Std.int(index / letters) + 1;
			final lowerAsciiA = 0x61;
			return [for (i in 0...alphabets) fromCharCode(lowerAsciiA + (index % letters))].join("");
		}

		var isOptional = false;
		if (type.startsWith("?")) {
			isOptional = true;
			type = type.substr(1);
		}

		if (type.startsWith(":"))
			return (if (isOptional) "?" else "") + getUniqueLetter(index) + type;
		else if (type.startsWith("(")) {
			final segmentsRe = ~/\((.*?)\)\s*:\s*(.*)/;
			if (!segmentsRe.match(type))
				return type;
			final args = segmentsRe.matched(1);
			final returnType = segmentsRe.matched(2);
			final fixedArgs = [
				for (arg in ~/\s*,\s*/g.split(args)) {
					final fixedArg = addNamesToSignatureType(arg, index);
					index++;
					fixedArg;
				}
			];
			return '(${fixedArgs.join(", ")}):$returnType';
		}
		return type;
	}
}

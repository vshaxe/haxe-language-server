package haxeLanguageServer.helper;

import String.fromCharCode;

class ArgumentNameHelper {
    public static function guessArgumentNames(types:Array<String>):Array<String> {
        return avoidDuplicates([for (type in types) guessArgumentName(type)]);
    }

    public static function guessArgumentName(type:String):String {
        type = TypeHelper.unwrapNullable(type);
        type = TypeHelper.getTypeWithoutParams(type);

        return switch (type) {
            case null, "": "unknown";
            case "Int": "i";
            case "Float": "f";
            case "Bool": "b";
            case "String": "s";
            case type if (type.startsWith("{")): "struct";
            case type:
                var segments = ~/(?=[A-Z][^A-Z]+$)/.split(type);
                var result = segments[segments.length - 1];
                result.substring(0, 1).toLowerCase() + result.substr(1);
        }
    }

    public static function avoidDuplicates(names:Array<String>):Array<String> {
        var currentOccurrence:Map<String, Int> = new Map();
        return [for (name in names) {
            var i = currentOccurrence[name];
            if (i == null) i = 0;

            if (names.occurrences(name) > 1) i++;
            currentOccurrence[name] = i;

            if (i > 0) name = name + i;
            name;
        }];
    }

    /**
        Adds argument names to types from signature completion.

        @param  type   a type like `(:Int, :Int):Void` or `:Int`
        @see https://github.com/HaxeFoundation/haxe/issues/6064
    **/
    public static function addNamesToSignatureType(type:String, index:Int = 0):String {
        inline function getUniqueLetter(index:Int) {
            var letters = 26;
            var alphabets = Std.int(index / letters) + 1;
            var lowerAsciiA = 0x61;
            return [for (i in 0...alphabets) fromCharCode(lowerAsciiA + (index % letters))].join("");
        }

        if (type.startsWith(":"))
             return getUniqueLetter(index) + type;
        else if (type.startsWith("(")) {
            var segmentsRe = ~/\((.*?)\)\s*:\s*(.*)/;
            if (!segmentsRe.match(type))
                return type;
            var args = segmentsRe.matched(1);
            var returnType = segmentsRe.matched(2);
            var fixedArgs = [for (arg in ~/\s*,\s*/g.split(args)) {
                var fixedArg = addNamesToSignatureType(arg, index);
                index++;
                fixedArg;
            }];
            return '(${fixedArgs.join(", ")}):$returnType';
        }
        return type;
    }
}
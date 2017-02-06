package haxeLanguageServer.helper;

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
}
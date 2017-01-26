package haxeLanguageServer.helper;

typedef FunctionFormattingConfig = {
    var argumentTypeHints:Bool;
    var returnTypeHint:ReturnTypeHintOption;
}

@:enum abstract ReturnTypeHintOption(String) {
    var Always = "always";
    var Never = "never";
    var NonVoid = "non-void";
}

class TypeHelper {
    static var groupRegex = ~/\$(\d+)/g;
    static var parenRegex = ~/^\((.*)\)$/;
    static var argNameRegex = ~/^(\??\w+) : /;
    static var monomorphRegex = ~/^Unknown<\d+>$/;
    static var nullRegex = ~/^Null<(\$\d+)>$/;
    static var typeRegex = ~/\b((_*[a-z]\w*\.)*)(_*[A-Z]\w*)\b/; // from the Haxe grammar

    static function getCloseChar(c:String):String {
        return switch (c) {
            case "(": ")";
            case "<": ">";
            case "{": "}";
            default: throw 'unknown opening char $c';
        }
    }

    public static function prepareSignature(type:String):String {
        return switch (parseDisplayType(type)) {
            case DTFunction(args, ret):
                printFunctionSignature(args, ret, {argumentTypeHints: true, returnTypeHint: Always});
            case DTValue(type):
                if (type == null) "" else type;
        }
    }

    public static function printFunctionDeclaration(args:Array<DisplayFunctionArgument>, ret:Null<String>, formatting:FunctionFormattingConfig):String {
        return "function" + printFunctionSignature(args, ret, formatting);
    }

    public static function printFunctionSignature(args:Array<DisplayFunctionArgument>, ret:Null<String>, formatting:FunctionFormattingConfig):String {
        var result = new StringBuf();
        result.addChar("(".code);
        var first = true;
        for (arg in args) {
            if (first) first = false else result.add(", ");
            result.add(printSignatureArgument(arg, formatting.argumentTypeHints));
        }
        result.addChar(")".code);
        if (shouldPrintReturnType(ret, formatting.returnTypeHint)) {
            result.addChar(":".code);
            result.add(ret);
        }
        return result.toString();
    }

    private static function shouldPrintReturnType(ret:Null<String>, option:ReturnTypeHintOption):Bool {
        if (ret == null) return false;
        return switch (option) {
            case Always: true;
            case Never: false;
            case NonVoid: ret != "Void";
        }
    }

    public static function printSignatureArgument(arg:DisplayFunctionArgument, typeHints:Bool):String {
        var result = arg.name;
        if (arg.opt)
            result = "?" + result;
        if (arg.type != null && typeHints) {
            result += ":";
            result += arg.type;
        }
        return result;
    }

    public static function parseFunctionArgumentType(argument:String):DisplayType {
        if (argument.startsWith("?"))
            argument = argument.substr(1);
        
        var colonIndex = argument.indexOf(":");
        var argumentType = argument.substr(colonIndex + 1);
        
        // urgh...
        while (argumentType.startsWith("Null<") && argumentType.endsWith(">")) {
            argumentType = argumentType.substring("Null<".length, argumentType.length - 1);
        }
        return parseDisplayType(argumentType);
    }

    public static function parseDisplayType(type:String):DisplayType {
        // replace arrows to ease parsing ">" in type params
        type = type.replace(" -> ", "%");

        // prepare a simple toplevel signature without nested arrows
        // nested arrow can be in () or <> and we don't need to modify them,
        // so we store them separately in `groups` map and replace their occurence
        // with a group name in the toplevel string
        var toplevel = new StringBuf();
        var groups = new Map();
        var closeStack = new haxe.ds.GenericStack();
        var depth = 0;
        var groupId = 0;
        for (i in 0...type.length) {
            var char = type.charAt(i);
            if (char == "(" || char == "<" || char == "{") {
                depth++;
                closeStack.add(getCloseChar(char));
                if (depth == 1) {
                    groupId++;
                    groups[groupId] = new StringBuf();
                    toplevel.add(char);
                    toplevel.add('$$$groupId');
                    continue;
                }
            } else if (char == closeStack.first()) {
                closeStack.pop();
                depth--;
            }

            if (depth == 0)
                toplevel.add(char);
            else
                groups[groupId].add(char);
        }

        // process a sigle type entry, replacing inner content from groups
        // and removing unnecessary parentheses
        function processType(type:String):String {
            type = groupRegex.map(type, function(r) {
                var groupId = Std.parseInt(r.matched(1));
                return groups[groupId].toString().replace("%", "->");
            });
            if (parenRegex.match(type))
                type = parenRegex.matched(1);
            return type;
        }

        // split toplevel signature by the "%" (which is actually "->")
        var parts = toplevel.toString().split("%");

        // get a return or variable type
        var returnType = processType(parts.pop());

        if (monomorphRegex.match(returnType))
            returnType = null;

        // if there is only the return type, it's a variable
        // otherwise `parts` contains function arguments
        if (parts.length > 0) {
            // format function arguments
            var args = new Array<DisplayFunctionArgument>();
            var argNameCode = "a".code;
            for (i in 0...parts.length) {
                var part = parts[i];

                // get argument name and type
                // if function is not a method, argument name is generated by its position
                var name, type, opt = false;
                if (argNameRegex.match(part)) {
                    name = argNameRegex.matched(1);
                    if (name.charCodeAt(0) == "?".code) {
                        name = name.substring(1);
                        opt = true;
                    }
                    type = argNameRegex.matchedRight();
                } else {
                    name = String.fromCharCode(argNameCode + i);
                    type = part;
                    if (type.charCodeAt(0) == "?".code) {
                        type = type.substring(1);
                        opt = true;
                    }
                }

                // strip Null<T> if argument is optional
                if (opt && nullRegex.match(type))
                    type = nullRegex.matched(1);

                type = processType(type);

                // we don't need to include the Void argument
                // because it represents absence of arguments
                if (type == "Void")
                    continue;

                var arg:DisplayFunctionArgument = {name: name};
                if (!monomorphRegex.match(type))
                    arg.type = type;
                if (opt)
                    arg.opt = true;
                args.push(arg);
            }
            return DTFunction(args, returnType);
        } else {
            return DTValue(returnType);
        }
    }
}

typedef DisplayFunctionArgument = {name:String, ?opt:Bool, ?type:String}

enum DisplayType {
    DTValue(type:Null<String>); // null if monomorph
    DTFunction(args:Array<DisplayFunctionArgument>, ret:Null<String>);
}

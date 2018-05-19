package haxeLanguageServer.helper;

import haxe.display.JsonModuleTypes;
using Lambda;

/**
    (Slightly modified) copy of haxe.display.JsonModuleTypesPrinter.
**/
class TypePrinter {
    var indent = "";

    public function new() {}

    public function printPath(path:JsonPath) {
        if (path.pack.length == 0) {
            return path.name;
        } else {
            return path.pack.join(".") + "." + path.name;
        }
    }

    public function printPathWithParams(path:JsonPathWithParams) {
        var s = printPath(path.path);
        if (path.params.length == 0) {
            return s;
        } else {
            var sparams = path.params.map(printType).join(", ");
            return '$s<$sparams>';
        }
    }

    public function printType<T>(t:JsonType<T>) {
        return switch (t.kind) {
            case TMono: "?";
            case TInst | TEnum | TType | TAbstract: printPathWithParams(t.args);
            case TDynamic:
                if (t.args == null) {
                    "Dynamic";
                } else {
                    var s = printTypeRec(t.args);
                    'Dynamic<$s>';
                }
            case TAnonymous:
                var fields = t.args.fields;
                var s = [for (field in fields) '${field.name}:${printTypeRec(field.type)}'].join(", ");
                '{$s}';
            case TFun:
                var hasNamed = false;
                function printFunctionArgument(arg:JsonFunctionArgument) {
                    if (arg.name != "") {
                        hasNamed = true;
                    }
                    return this.printFunctionArgument(arg);
                }
                var args = t.args.args.map(printFunctionArgument);
                var r = printTypeRec(t.args.ret);
                switch (args.length) {
                    case 0: '() -> $r';
                    case 1 if (hasNamed): '(${args[0]}) -> $r';
                    case 1 : '${args[0]} -> $r';
                    case _:
                        var busy = args.fold((args, i) -> i + args.length, 0);
                        if (busy < 50) {
                            var s = args.join(", ");
                            '($s) -> $r';
                        } else {
                            var s = args.join(',\n $indent');
                            '($s)\n$indent-> $r';
                        }
                }
        }
    }

    function printTypeRec<T>(t:JsonType<T>) {
        var old = indent;
        indent += "  ";
        var t = printType(t);
        indent = old;
        return t;
    }

    public function printFunctionArgument(arg:JsonFunctionArgument) {
        return (arg.opt ? "?" : "") + (arg.name == "" ? "" : arg.name + ":") + printTypeRec(arg.t);
    }
}

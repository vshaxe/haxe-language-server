package haxeLanguageServer.protocol.helper;

import haxe.ds.Option;
import haxe.display.JsonModuleTypes;
import haxeLanguageServer.protocol.Display;
using Lambda;

/**
    (Slightly modified) copy of haxe.display.JsonModuleTypesPrinter.
**/
class DisplayPrinter {
    final wrap:Bool;
    var indent = "";

    public function new(wrap:Bool = false) {
        this.wrap = wrap;
    }

    public function printPath(path:JsonPath) {
        return path.name;
        /*if (path.pack.length == 0) {
            return path.name;
        } else {
            return path.pack.join(".") + "." + path.name;
        }*/
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
                        if (busy < 50 || !wrap) {
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

    public function printEmptyFunctionDefinition(field:JsonClassField) {
        var vis = field.isPublic ? "public " : "";
        function extractFunctionSignature<T>(type:JsonType<T>) {
            return switch (type.kind) {
                case TFun: type.args;
                case _: throw "function expected";
            }
        }
        var sig = extractFunctionSignature(field.type);
        var sig = sig.args.map(printFunctionArgument).join(", ");
        return vis + "function " + field.name + "(" + sig + ")";
    }

    /**
        Prints a type declaration in the form of `extern interface ArrayAccess<T>`.
        (`modifiers... keyword Name<Params>`)
    **/
    public function printTypeDeclaration(type:ModuleType):String {
        var components = [];
        if (type.isPrivate) components.push("private");
        if (type.meta.exists(meta -> meta.name == ":final")) components.push("final");
        if (type.isExtern) components.push("extern");
        components.push(switch (type.kind) {
            case Class: "class";
            case Interface: "interface";
            case Enum: "enum";
            case Abstract: "abstract";
            case EnumAbstract: "enum abstract";
            case TypeAlias | Struct: "typedef";
            case ImportAlias: "import as";
        });
        var typeName = type.name;
        if (type.params.length > 0) {
            typeName += "<" + type.params.map(param -> param.name).join(", ") + ">";
        }
        components.push(typeName);
        return components.join(" ");
    }

    public function printQualifiedTypePath(type:ModuleType):String {
        var result = type.pack.join(".");
        if (type.pack.length > 0) {
            result += ".";
        }
        result += type.moduleName;
        if (type.name != type.moduleName) {
            result += "." + type.name;
        }
        if (type.pack.length == 0 && type.importStatus == Shadowed) {
            result = "std." + result;
        }
        return result;
    }

    public function printClassFieldOrigin<T>(origin:ClassFieldOrigin<T>, kind:CompletionItemKind<Dynamic>, quote:String):Option<String> {
        if (kind == EnumAbstractValue || origin.kind == cast Unknown) {
            return None;
        }
        if (origin.args == null && origin.kind != cast BuiltIn) {
            return None;
        }
        var q = quote;
        return Some("from " + switch (origin.kind) {
            case Self:
                '$q${origin.args.name}$q';
            case Parent:
                'parent type $q${origin.args.name}$q';
            case StaticExtension:
                '$q${origin.args.name}$q (static extension method)';
            case StaticImport:
                'static import';
            case AnonymousStructure:
                'anonymous structure';
            case BuiltIn:
                'compiler (built-in)';
            case Unknown:
                ''; // already handled
        });
    }

    public function printLocalOrigin(origin:LocalOrigin):String {
        return switch (origin) {
            case LocalVariable: "local";
            case Argument: "argument";
            case ForVariable: "for variable";
            case PatternVariable: "pattern variable";
            case CatchVariable: "catch variable";
            case LocalFunction: "local function";
        }
    }

    public function printEnumField<T>(field:JsonEnumField, snippets:Bool) {
        return switch (field.type.kind) {
            case TEnum:
                field.name + ":";
            case TFun:
                var signature:JsonFunctionSignature = field.type.args;
                var text = '${field.name}(';
                for (i in 0...signature.args.length) {
                    var arg = signature.args[i];
                    text += if (snippets) {
                        '$${${i+1}:${arg.name}}';
                    } else {
                        arg.name;
                    }

                    if (i < signature.args.length - 1) {
                        text += ", ";
                    }
                }
                text + "):";
            case _:
                "";
        }
    }
}

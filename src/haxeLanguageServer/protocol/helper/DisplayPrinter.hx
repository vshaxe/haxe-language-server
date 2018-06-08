package haxeLanguageServer.protocol.helper;

import haxeLanguageServer.helper.TypeHelper.FunctionFormattingConfig;
import haxe.ds.Option;
import haxe.display.JsonModuleTypes;
import haxeLanguageServer.protocol.Display;
using Lambda;

enum PathPrinting {
    /**
        Always print the full dot path for types.
    **/
    Always;
    /**
        Only print the full dot path when unimported or shadowed (so it's always qualified).
    **/
    Qualified;
    /**
        Only print the full dot path for shadowed types.
    **/
    Shadowed;
}

/**
    (Slightly modified) copy of haxe.display.JsonModuleTypesPrinter.
**/
class DisplayPrinter {
    final wrap:Bool;
    final pathPrinting:PathPrinting;
    final functionFormatting:FunctionFormattingConfig;
    var indent = "";

    public function new(wrap:Bool = false, ?pathPrinting:PathPrinting, ?functionFormatting:FunctionFormattingConfig) {
        this.wrap = wrap;
        this.pathPrinting = pathPrinting;
        if (this.pathPrinting == null) {
            this.pathPrinting = Qualified;
        }
        this.functionFormatting = functionFormatting;
        if (this.functionFormatting == null) {
            this.functionFormatting = {
                useArrowSyntax: true,
                returnTypeHint: NonVoid,
                argumentTypeHints: true
            }
        }
    }

    public function printPath(path:JsonPath) {
        function print(qualified:Bool) {
            return if (!qualified || path.pack.length == 0) {
                path.name;
            } else {
                path.pack.join(".") + "." + path.name;
            }
        }
        return print(switch(pathPrinting) {
            case Always: true;
            case Qualified: path.importStatus != Imported;
            case Shadowed: path.importStatus == Shadowed;
        });
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

    public function printFunctionArgument<T>(arg:JsonFunctionArgument) {
        var optional = false;
        var concreteType = arg.t;
        switch (arg.t.kind) {
            case TAbstract:
                var typePath:JsonPathWithParams = arg.t.args;
                if (typePath.path.pack.length == 0 && typePath.path.name == "Null") {
                    concreteType = typePath.params[0]; // TODO: recurse (for Null<Null<T>>)?
                    optional = true;
                }
            case _:
        }
        var argument = (optional ? "?" : "") + arg.name;
        if (functionFormatting.argumentTypeHints) {
            argument += (arg.name == "" ? "" : ":") + printTypeRec(concreteType);
        }
        if (arg.value != null) {
            argument += " = " + arg.value.string;
        }
        return argument;
    }

    public function printCallArguments<T>(signature:JsonFunctionSignature, printFunctionArgument:JsonFunctionArgument->String) {
        return "(" + signature.args.map(printFunctionArgument).join(", ") + ")";
    }

    public function printTypeParameters(params:JsonTypeParameters) {
        return if (params.length == 0) {
            "";
        } else {
            "<" + params.map(param -> {
                var s = param.name;
                if (param.constraints.length > 0) {
                    s += ":" + param.constraints.map(constraint -> printTypeRec(constraint)).join(" & ");
                }
                s;
            }).join(", ") + ">";
        }
    }

    public function printEmptyFunctionDefinition<T>(field:JsonClassField, concreteType:JsonType<T>) {
        var signature = concreteType.extractFunctionSignature();
        var definition = "function " + field.name + printTypeParameters(field.params) + printCallArguments(signature, printFunctionArgument);
        var returnStyle = functionFormatting.returnTypeHint;
        if (returnStyle == Always || (returnStyle == NonVoid && !signature.ret.isVoid())) {
            definition += ":" + printTypeRec(signature.ret);
        }
        return definition;
    }

    public function printOverrideDefinition<T>(field:JsonClassField, concreteType:JsonType<T>, indent:String) {
        var signature = concreteType.extractFunctionSignature();
        var returnKeyword = if (signature.ret.isVoid()) "" else "return ";
        var arguments = printCallArguments(signature, arg -> arg.name);
        var lineBreak = if (functionFormatting.placeOpenBraceOnNewLine) "\n" else " ";
        return printEmptyFunctionDefinition(field, concreteType) + '$lineBreak{\n${indent}$${1:${returnKeyword}super.${field.name}$arguments;$0}\n}';
    }

    static final castRegex = ~/(cast )+/;
    public function printFieldDefinition<T1,T2>(field:JsonClassField, concreteType:JsonType<T1>) {
        var type = printType(concreteType);
        var name = field.name;
        var kind:JsonFieldKind<T2> = field.kind;
        var access = if (field.isPublic) "public" else "private";
        var staticKeyword = if (field.scope == Static) "static " else "";
        return switch (kind.kind) {
            case FVar:
                var inlineKeyword = if (kind.args.write.kind == AccInline) "inline " else "";
                var keyword = if (kind.args.write.kind == AccCtor) "final" else "var";
                var read = printAccessor(kind.args.read, true);
                var write = printAccessor(kind.args.write, false);
                var accessors = if (read != null && write != null) '($read, $write)' else "";
                var definition = '$access $staticKeyword$keyword $inlineKeyword$name$accessors:$type';
                if (field.expr != null) {
                    var expr = castRegex.replace(field.expr.string, "");
                    definition += " = " + expr;
                }
                definition;
            case FMethod:
                var methodKind = switch (kind.args) {
                    case MethNormal: "";
                    case MethInline: "inline ";
                    case MethDynamic: "dynamic ";
                    case MethMacro: "macro ";
                }
                var finalKeyword = if (field.meta.hasMeta(Final)) "final " else "";
                var definition = printEmptyFunctionDefinition(field, concreteType);
                '$access $staticKeyword$finalKeyword$methodKind$definition';
        };
    }

    public function printAccessor<T>(access:JsonVarAccess<T>, isRead:Bool) {
        return switch (access.kind) {
            case AccNormal: null;
            case AccNo: null;
            case AccNever: "never";
            case AccResolve: null;
            case AccCall: if (isRead) "get" else "set";
            case AccInline: null;
            case AccRequire: null;
            case AccCtor: null;
        }
    }

    /**
        Prints a type declaration in the form of `extern interface ArrayAccess<T>`.
        (`modifiers... keyword Name<Params>`)
    **/
    public function printTypeDeclaration(type:ModuleType):String {
        var components = [];
        if (type.isPrivate) components.push("private");
        if (type.meta.hasMeta(Final)) components.push("final");
        if (type.isExtern) components.push("extern");
        components.push(switch (type.kind) {
            case Class: "class";
            case Interface: "interface";
            case Enum: "enum";
            case Abstract: "abstract";
            case EnumAbstract: "enum abstract";
            case TypeAlias | Struct: "typedef";
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
        if (kind == EnumAbstractField || origin.kind == cast Unknown) {
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

package haxeLanguageServer.protocol.helper;

import haxeLanguageServer.protocol.Display;
import haxe.display.JsonModuleTypes;
using Lambda;

class Helper {
    public static function getDocumentation<T>(item:CompletionItem<T>):JsonDoc {
        return switch (item.kind) {
            case ClassField | EnumAbstractField: item.args.field.doc;
            case EnumField: item.args.field.doc;
            case Type: item.args.doc;
            case Metadata: item.args.doc;
            case _: null;
        }
    }

    public static function extractFunctionSignature<T>(type:JsonType<T>) {
        return switch (type.kind) {
            case TFun: type.args;
            case _: throw "function expected";
        }
    }

    public static function resolveImports<T>(type:JsonType<T>):Array<JsonPath> {
        function rec(type:JsonType<T>):Array<JsonPath> {
            return switch (type.kind) {
                case TMono: [];
                case TInst | TEnum | TType | TAbstract:
                    if (type.args.path.importStatus == Unimported) {
                        [type.args.path];
                    } else {
                        [];
                    }
                case TFun:
                    var signature = type.args;
                    signature.args.map(arg -> rec(arg.t)).flatten().array().concat(rec(signature.ret));
                case TAnonymous:
                    type.args.fields.map(field -> rec(field.type)).flatten().array();
                case TDynamic:
                    if (type.args != null) {
                        rec(type.args);
                    } else {
                        [];
                    }
            }
        }
        return rec(type).filterDuplicates((e1, e2) -> Reflect.compare(e1, e2) != 0);
    }

    public static function hasMeta(meta:JsonMetadata, name:CompilerMetadata) {
        return meta.exists(meta -> meta.name == cast name);
    }

    public static function isOperator(field:JsonClassField) {
        return field.meta.hasMeta(Op) || field.meta.hasMeta(Resolve) || field.meta.hasMeta(ArrayAccess);
    }

    public static function isEnumAbstractField(field:JsonClassField) {
        return field.meta.hasMeta(Enum) && field.meta.hasMeta(Value);
    }

    public static function isVoid<T>(type:JsonType<T>) {
        return switch (type.kind) {
            case TAbstract if (type.args.path.name == "Void"): true;
            case _: false;
        }
    }

    public static function isStructure<T>(?origin:ClassFieldOrigin<T>) {
        if (origin == null) {
            return null;
        }
        return switch (origin.kind) {
            case Self | StaticImport | Parent | StaticExtension:
                var moduleType:JsonModuleType<Dynamic> = origin.args;
                if (moduleType == null) {
                    return false;
                }
                switch (moduleType.kind) {
                    case Typedef:
                        var jsonTypedef:JsonTypedef = moduleType.args;
                        jsonTypedef.type.removeNulls().type.kind == TAnonymous;
                    case _: false;
                }
            case AnonymousStructure: true;
            case _: false;
        }
        return false;
    }

    public static function removeNulls<T>(type:JsonType<T>, optional:Bool = false):{type:JsonType<T>, optional:Bool} {
        switch (type.kind) {
            case TAbstract:
                var path:JsonPathWithParams = type.args;
                if (path.path.pack.length == 0 && path.path.name == "Null") {
                    if (path.params != null && path.params[0] != null) {
                        return removeNulls(path.params[0], true);
                    }
                }
            case _:
        }
        return {type: type, optional: optional};
    }

    public static function hasMandatoryTypeParameters(type:ModuleType):Bool {
        // Dynamic is a special case regarding this in the compiler
        if (type.name == "Dynamic" && type.pack.length == 0) {
            return false;
        }
        return type.params != null && type.params.length > 0;
    }
}

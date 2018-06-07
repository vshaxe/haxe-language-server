package haxeLanguageServer.protocol.helper;

import haxeLanguageServer.protocol.Display;
import haxe.display.JsonModuleTypes;
using Lambda;

class Helper {
    public static function getDocumentation<T>(item:CompletionItem<T>):JsonDoc {
        return switch (item.kind) {
            case ClassField | EnumAbstractValue: item.args.field.doc;
            case EnumValue: item.args.field.doc;
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
}

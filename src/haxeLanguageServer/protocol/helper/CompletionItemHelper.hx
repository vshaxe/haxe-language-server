package haxeLanguageServer.protocol.helper;

import haxeLanguageServer.protocol.Display.CompletionItem;
import haxe.display.JsonModuleTypes.JsonDoc;

class CompletionItemHelper {
    public static function getDocumentation<T>(item:CompletionItem<T>):JsonDoc {
        return switch (item.kind) {
            case ClassField | EnumAbstractValue: item.args.field.doc;
            case EnumValue: item.args.field.doc;
            case Type: item.args.doc;
            case Metadata: item.args.doc;
            case _: null;
        }
    }
}
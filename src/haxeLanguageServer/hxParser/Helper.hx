package haxeLanguageServer.hxParser;

import hxParser.ParseTree;
import hxParser.WalkStack;
using hxParser.WalkStackTools;
using Lambda;

class Helper {
    public static function isOperator(stack:WalkStack, metadata:Array<Metadata>):Bool {
        if (getAbstractDecl(stack) == null) {
            return false;
        }
        return metadata.exists(metadata -> switch (metadata) {
            case Simple(token) if (token.text == "@:arrayAccess" || token.text == "@:resolve"): true;
            case WithArgs(token, _, _) if (token.text == "@:op("): true;
            case _: false;
        });
    }

    public static function isAbstractEnumField(stack:WalkStack, modifiers:Array<FieldModifier>) {
        return !isStatic(modifiers) && isInAbstractEnum(stack);
    }

    public static function isInAbstractEnum(stack:WalkStack):Bool {
        var abstractDecl = getAbstractDecl(stack);
        if (abstractDecl == null) {
            return false;
        }
        return abstractDecl.annotations.metadata.exists(meta -> switch (meta) {
            case Simple(token) if (token.text == "@:enum"): true;
            case _: false;
        });
    }

    static function getAbstractDecl(stack:WalkStack):Null<AbstractDecl> {
        var abstractDecl = null;
        stack.find(stack -> switch (stack) {
            case Node(Decl_AbstractDecl(decl), _):
                abstractDecl = decl;
                false;
            case _: false;
        });
        return abstractDecl;
    }

    public static function isInline(modifiers:Array<FieldModifier>):Bool {
        return modifiers.exists(modifier -> modifier.match(FieldModifier.Inline(_)));
    }

    public static function isStatic(modifiers:Array<FieldModifier>):Bool {
        return modifiers.exists(modifier -> modifier.match(FieldModifier.Static(_)));
    }
}
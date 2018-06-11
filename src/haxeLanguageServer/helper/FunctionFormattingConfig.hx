package haxeLanguageServer.helper;

import haxe.display.JsonModuleTypes;

typedef FunctionFormattingConfig = {
    var ?argumentTypeHints:Bool;
    var ?returnTypeHint:ReturnTypeHintOption;
    var ?useArrowSyntax:Bool;
    var ?placeOpenBraceOnNewLine:Bool;
    var ?explicitPublic:Bool;
    var ?explicitPrivate:Bool;
    var ?explicitNull:Bool;
}

enum abstract ReturnTypeHintOption(String) {
    var Always = "always";
    var Never = "never";
    var NonVoid = "non-void";
}

class FunctionFormattingConfigHelper {
    public static function printReturn(config:FunctionFormattingConfig, signature:JsonFunctionSignature) {
        if (config.useArrowSyntax) {
            return false;
        }
        var returnStyle = config.returnTypeHint;
        return returnStyle == Always || (returnStyle == NonVoid && !signature.ret.isVoid());
    }
}

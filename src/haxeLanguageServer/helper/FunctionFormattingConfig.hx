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
    var ?prefixPackages:Bool; // NOT part of the user settings, only needed for Haxe versions < 4.0.0-preview.4
}

enum abstract ReturnTypeHintOption(String) {
    var Always = "always";
    var Never = "never";
    var NonVoid = "non-void";
}

class FunctionFormattingConfigHelper {
    public static function printReturn(config:FunctionFormattingConfig, signature:JsonFunctionSignature) {
        var returnStyle = config.returnTypeHint;
        return returnStyle == Always || (returnStyle == NonVoid && !signature.ret.isVoid());
    }
}

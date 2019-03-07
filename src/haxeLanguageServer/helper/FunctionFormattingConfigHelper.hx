package haxeLanguageServer.helper;

import haxe.display.JsonModuleTypes;
import haxeLanguageServer.Configuration.FunctionFormattingConfig;

class FunctionFormattingConfigHelper {
	public static function printReturn(config:FunctionFormattingConfig, signature:JsonFunctionSignature) {
		if (config.useArrowSyntax) {
			return false;
		}
		var returnStyle = config.returnTypeHint;
		return returnStyle == Always || (returnStyle == NonVoid && !signature.ret.isVoid());
	}
}

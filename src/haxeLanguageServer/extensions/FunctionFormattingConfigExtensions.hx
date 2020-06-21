package haxeLanguageServer.extensions;

import haxe.display.JsonModuleTypes;
import haxeLanguageServer.Configuration.FunctionFormattingConfig;

function shouldPrintReturn(config:FunctionFormattingConfig, signature:JsonFunctionSignature) {
	if (config.useArrowSyntax) {
		return false;
	}
	final returnStyle = config.returnTypeHint;
	return returnStyle == Always || (returnStyle == NonVoid && !signature.ret.isVoid());
}

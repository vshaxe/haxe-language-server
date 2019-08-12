package haxeLanguageServer.features.completion;

import haxe.display.Display.CompletionMode;
import haxeLanguageServer.helper.ImportHelper.ImportPosition;
import haxeLanguageServer.tokentree.TokenContext;

typedef CompletionContextData = {
	var replaceRange:Range;
	var mode:CompletionMode<Dynamic>;
	var doc:TextDocument;
	var indent:String;
	var lineAfter:String;
	var params:CompletionParams;
	var importPosition:ImportPosition;
	var tokenContext:TokenContext;
	var isResolve:Bool;
}

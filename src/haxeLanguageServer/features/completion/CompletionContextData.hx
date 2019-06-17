package haxeLanguageServer.features.completion;

import haxeLanguageServer.helper.ImportHelper.ImportPosition;
import haxeLanguageServer.tokentree.TokenContext;
import haxeLanguageServer.protocol.Display.CompletionMode;

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

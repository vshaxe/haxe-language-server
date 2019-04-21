package haxeLanguageServer.features.completion;

import haxeLanguageServer.tokentree.TokenContext;
import haxeLanguageServer.protocol.Display.CompletionMode;

typedef CompletionContextData = {
	var replaceRange:Range;
	var mode:CompletionMode<Dynamic>;
	var doc:TextDocument;
	var indent:String;
	var textBefore:String;
	var lineAfter:String;
	var completionPosition:Position;
	var importPosition:Position;
	var tokenContext:TokenContext;
}

package haxeLanguageServer.features.completion;

import tokentree.TokenTree;
import haxeLanguageServer.protocol.Display.CompletionMode;

typedef CompletionContextData = {
	var replaceRange:Range;
	var mode:CompletionMode<Dynamic>;
	var doc:TextDocument;
	var indent:String;
	var lineAfter:String;
	var completionPosition:Position;
	var importPosition:Position;
	var token:TokenTree;
}

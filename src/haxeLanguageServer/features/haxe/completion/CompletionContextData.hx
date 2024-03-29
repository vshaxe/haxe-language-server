package haxeLanguageServer.features.haxe.completion;

import haxe.display.Display.CompletionMode;
import haxeLanguageServer.helper.ImportHelper.ImportPosition;
import haxeLanguageServer.tokentree.TokenContext;

typedef CompletionContextData = {
	final replaceRange:Range;
	final mode:CompletionMode<Dynamic>;
	final doc:HxTextDocument;
	final indent:String;
	final lineAfter:String;
	final params:CompletionParams;
	final importPosition:ImportPosition;
	final tokenContext:TokenContext;
	var isResolve:Bool;
}

package haxeLanguageServer.features.completion;

import haxeLanguageServer.helper.FunctionFormattingConfig;
import haxe.display.JsonModuleTypes;
import haxeLanguageServer.helper.ImportHelper;
import haxeLanguageServer.protocol.helper.DisplayPrinter;
import haxeLanguageServer.protocol.Display.CompletionMode;
using Lambda;

typedef CompletionContextData = {
    var replaceRange:Range;
    var mode:CompletionMode<Dynamic>;
    var doc:TextDocument;
    var indent:String;
    var lineAfter:String;
    var completionPosition:Position;
    var importPosition:Position;
}

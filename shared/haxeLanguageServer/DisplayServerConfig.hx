package haxeLanguageServer;

import haxe.DynamicAccess;
import haxe.display.Server.ConfigurePrintParams;

typedef DisplayServerConfig = {
	var path:String;
	var env:DynamicAccess<String>;
	var arguments:Array<String>;
	var useSocket:Bool;
	var print:ConfigurePrintParams;
}

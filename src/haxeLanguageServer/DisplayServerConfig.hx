package haxeLanguageServer;

import haxeLanguageServer.protocol.Server.ConfigurePrintParams;

typedef DisplayServerConfig = {
    var path:String;
    var env:haxe.DynamicAccess<String>;
    var arguments:Array<String>;
    var ?print:ConfigurePrintParams;
}

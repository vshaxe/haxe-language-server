package haxeLanguageServer;

typedef DisplayServerConfig = {
    var path:String;
    var env:haxe.DynamicAccess<String>;
    var arguments:Array<String>;
}

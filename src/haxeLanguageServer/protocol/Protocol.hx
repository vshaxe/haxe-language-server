package haxeLanguageServer.protocol;

import jsonrpc.Types;

@:publicFields
class Methods {
    /**
        The initialize request is sent from the client to Haxe to determine the capabilities.
    **/
    static inline var Initialize = new HaxeRequestMethod<InitializeParams,InitializeResult>("initialize");
}

/* Initialize */

typedef InitializeParams = {
    var ?supportsResolve:Bool;
}

/**
    Represents a semantic version, see https://semver.org/.
**/
typedef Version = {
    var major:Int;
    var minor:Int;
    var patch:Int;
    var pre:String;
    var build:String;
}

typedef InitializeResult = Response<{
    var protocolVersion:Version;
    var haxeVersion:Version;
    var methods:Array<String>;
}>;

/* general protocol types */

typedef Timer = {
    final name:String;
    final path:String;
    final info:String;
    final time:Float;
    final calls:Int;
    final percentTotal:Float;
    final percentParent:Float;
    @:optional final children:Array<Timer>;
}

typedef Response<T> = {
    final result:T;
    /** UNIX timestamp at the moment the data was sent. **/
    final timestamp:Float;
    /** Only sent if `--times` is enabled. **/
    @:optional final timers:Timer;
}

typedef FileParams = {
    var file:FsPath;
}

typedef HaxeRequestMethod<TParams,TResponse> = RequestMethod<TParams,TResponse,NoData,NoData>;
typedef HaxeNotificationMethod<TParams> = NotificationMethod<TParams,NoData>;

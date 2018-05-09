package haxeLanguageServer.server;

import jsonrpc.Types;

// TODO: use URIs instead of fs paths?

/**
    Methods of the JSON-RPC-based `--display` protocol in Haxe 4.
**/
@:publicFields
class HaxeMethods {
    /**
        The initialize request is sent from the client to Haxe to determine the capabilities.
    **/
    static inline var Initialize = new HaxeRequestMethod<InitializeParams,InitializeResult>("initialize");

    /**
        The goto definition request is sent from the client to Haxe to resolve the definition location(s) of a symbol at a given text document position.
    **/
    static inline var GotoDefinition = new HaxeRequestMethod<PositionParams,Array<Location>>("textDocument/definition");

    static inline var Hover = new HaxeRequestMethod<PositionParams,Null<HoverResult>>("textDocument/hover");
}

/* Initialize */

typedef InitializeParams = {

}

typedef HaxeCapabilities = {
    > ServerCapabilities,
}

typedef InitializeResult = {
    var capabilities:HaxeCapabilities;
}

/* Definition */

typedef PositionParams = {
    var file:FsPath;

    /**
        Unicode character offset in the file.
    **/
    var offset:Int;
}

typedef Location = {
    var file:FsPath;
    var range:Range;
}

/* Hover */

typedef HoverResult = {
    var documentation:Null<String>;
    var range:Range;
    var type:Null<haxe.rtti.JsonModuleTypes.JsonType<Dynamic>>;
}

typedef HaxeRequestMethod<TParams,TResponse> = RequestMethod<TParams,TResponse,NoData,NoData>;
typedef HaxeNotificationMethod<TParams> = NotificationMethod<TParams,NoData>;

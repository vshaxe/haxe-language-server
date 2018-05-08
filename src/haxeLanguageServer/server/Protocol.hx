package haxeLanguageServer.server;

import jsonrpc.Types;

/**
    Methods of the JSON-RPC-based `--display` protocol in Haxe 4.
**/
class Protocol {
    /**
        The goto definition request is sent from the client to Haxe to resolve the definition location(s) of a symbol at a given text document position.
    **/
    static inline var GotoDefinition = new RequestMethod<PositionParams,Array<Location>,NoData,NoData>("definition");
}

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

package haxeLanguageServer.protocol;

import jsonrpc.Types.NoData;
import haxeLanguageServer.protocol.Types;

@:publicFields
class ServerMethods {
    /**
        This request is sent from the client to Haxe to explore the class paths. This effectively creates a cache for toplevel completion.
    **/
    static inline var ReadClassPaths = new HaxeRequestMethod<NoData,Response<NoData>>("server/readClassPaths");

    static inline var Configure = new HaxeRequestMethod<ConfigureParams,Response<NoData>>("server/configure");

    static inline var Invalidate = new HaxeRequestMethod<FileParams,Response<NoData>>("server/invalidate");
}

/* Configure */

typedef ConfigureParams = {
    var noModuleChecks:Bool;
}

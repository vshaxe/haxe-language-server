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

typedef ConfigurePrintParams = {
	@:optional var addedDirectory:Bool;
	@:optional var foundDirectories:Bool;
	@:optional var changedDirectories:Bool;
	@:optional var modulePathChanged:Bool;
	@:optional var notCached:Bool;
	@:optional var parsed:Bool;
	@:optional var removedDirectory:Bool;
	@:optional var reusing:Bool;
	@:optional var skippingDep:Bool;
	@:optional var unchangedContent:Bool;
	@:optional var cachedModules:Bool;
	@:optional var arguments:Bool;
	@:optional var completion:Bool;
	@:optional var defines:Bool;
	@:optional var signature:Bool;
	@:optional var displayPosition:Bool;
	@:optional var stats:Bool;
	@:optional var message:Bool;
	@:optional var socketMessage:Bool;
	@:optional var uncaughtError:Bool;
	@:optional var newContext:Bool;
}

typedef ConfigureParams = {
    @:optional var noModuleChecks:Bool;
    @:optional var print:ConfigurePrintParams;
}

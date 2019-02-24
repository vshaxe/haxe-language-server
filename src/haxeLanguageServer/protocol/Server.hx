package haxeLanguageServer.protocol;

import jsonrpc.Types.NoData;
import haxeLanguageServer.protocol.Protocol;

@:publicFields
class ServerMethods {
	/**
		This request is sent from the client to Haxe to explore the class paths. This effectively creates a cache for toplevel completion.
	**/
	static inline var ReadClassPaths = new HaxeRequestMethod<NoData, Response<{?files:Int}>>("server/readClassPaths");
	static inline var Configure = new HaxeRequestMethod<ConfigureParams, Response<NoData>>("server/configure");
	static inline var Invalidate = new HaxeRequestMethod<FileParams, Response<NoData>>("server/invalidate");
}

/* Configure */
typedef ConfigurePrintParams = {
	var ?addedDirectory:Bool;
	var ?foundDirectories:Bool;
	var ?changedDirectories:Bool;
	var ?modulePathChanged:Bool;
	var ?notCached:Bool;
	var ?parsed:Bool;
	var ?removedDirectory:Bool;
	var ?reusing:Bool;
	var ?skippingDep:Bool;
	var ?unchangedContent:Bool;
	var ?cachedModules:Bool;
	var ?arguments:Bool;
	var ?completion:Bool;
	var ?defines:Bool;
	var ?signature:Bool;
	var ?displayPosition:Bool;
	var ?stats:Bool;
	var ?message:Bool;
	var ?socketMessage:Bool;
	var ?uncaughtError:Bool;
	var ?newContext:Bool;
}

typedef ConfigureParams = {
	var ?noModuleChecks:Bool;
	var ?print:ConfigurePrintParams;
}

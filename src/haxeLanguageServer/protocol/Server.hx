package haxeLanguageServer.protocol;

import jsonrpc.Types.NoData;
import haxe.display.JsonModuleTypes;
import haxeLanguageServer.protocol.Protocol;

@:publicFields
class ServerMethods {
	/**
		This request is sent from the client to Haxe to explore the class paths. This effectively creates a cache for toplevel completion.
	**/
	static inline var ReadClassPaths = new HaxeRequestMethod<NoData, Response<{?files:Int}>>("server/readClassPaths");
	static inline var Configure = new HaxeRequestMethod<ConfigureParams, Response<NoData>>("server/configure");
	static inline var Invalidate = new HaxeRequestMethod<FileParams, Response<NoData>>("server/invalidate");
	static inline var Contexts = new HaxeRequestMethod<NoData, Response<Array<HaxeServerContext>>>("server/contexts");
	static inline var Memory = new HaxeRequestMethod<NoData, Response<HaxeMemoryResult>>("server/memory");
	static inline var Modules = new HaxeRequestMethod<ContextParams, Response<Array<String>>>("server/modules");
	static inline var Module = new HaxeRequestMethod<ModuleParams, Response<JsonModule>>("server/module");
	static inline var Files = new HaxeRequestMethod<ContextParams, Response<Array<JsonServerFile>>>("server/files");
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
	final ?noModuleChecks:Bool;
	final ?print:ConfigurePrintParams;
}

/* Contexts */
typedef HaxeServerContext = {
	final index:Int;
	final desc:String;
	final signature:String;
	final platform:String;
	final classPaths:Array<String>;
	final defines:Array<{key:String, value:String}>;
}

typedef ModuleId = {
	final path:String;
	final sign:String;
}

typedef JsonModule = {
	final id:Int;
	final path:JsonModulePath;
	final types:Array<JsonTypePath>;
	final file:String;
	final sign:String;
	final dependencies:Array<ModuleId>;
}

typedef JsonServerFile = {
	final file:String;
	final time:Float;
	final pack:String;
	final moduleName:Null<String>;
}

/* Memory */
typedef HaxeMemoryResult = {
	final contexts:Array<{
		final context:Null<HaxeServerContext>;
		final size:Int;
		final modules:Array<ModulesSizeResult>;
	}>;
	final memory:{
		final totalCache:Int;
		final haxelibCache:Int;
		final parserCache:Int;
		final moduleCache:Int;
	}
}

typedef SizeResult = {
	final path:String;
	final size:Int;
}

typedef ModuleTypeSizeResult = SizeResult & {
	final fields:Array<SizeResult>;
}

typedef ModulesSizeResult = SizeResult & {
	final types:Array<ModuleTypeSizeResult>;
}

typedef ContextParams = {
	final signature:String;
}

typedef ModuleParams = ContextParams & {
	final path:String;
}

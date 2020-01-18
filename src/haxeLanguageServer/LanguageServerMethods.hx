package haxeLanguageServer;

import haxe.display.Protocol.Response;
import haxeLanguageServer.Configuration.DisplayServerConfig;
import jsonrpc.Types;

/**
	Custom, Haxe-Language-Server-specific methods that are not part of the Language Server Protocol.
**/
@:publicFields
class LanguageServerMethods {
	/**
		This notification is sent from the client to the server when display arguments have changed.
	**/
	static inline var DidChangeDisplayArguments = new NotificationType<{arguments:Array<String>}>("haxe/didChangeDisplayArguments");

	/**
		This notification is sent from the client to the server when display arguments have changed.
	**/
	static inline var DidChangeDisplayServerConfig = new NotificationType<DisplayServerConfig>("haxe/didChangeDisplayServerConfig");

	/**
		This request is sent from the client to the server to determine the haxe package for a given file,
		based on class paths configuration.
	**/
	static inline var DeterminePackage = new RequestType<{fsPath:String}, {pack:String}, NoData>("haxe/determinePackage");

	/**
		This notification is sent from the client to the server to run a global diagnostics check.
	**/
	static inline var RunGlobalDiagnostics = new NotificationType<NoData>("haxe/runGlobalDiagnostics");

	/**
		This notification is sent from the server to the client when a global diagnostics check was finished successfully.
	**/
	static inline var DidRunRunGlobalDiagnostics = new NotificationType<NoData>("haxe/didRunGlobalDiagnostics");

	/**
		This notification is sent from the client to the server when the active text editor has changed.
	**/
	static inline var DidChangeActiveTextEditor = new NotificationType<{uri:DocumentUri}>("haxe/didChangeActiveTextEditor");

	/**
		This notification is sent from the server to the client when some long-running process is started.
		Client may display this somehow in the UI. The `id` is used later for sending `ProgressStop` notification.
	**/
	static inline var ProgressStart = new NotificationType<{id:Int, title:String}>("haxe/progressStart");

	/**
		This notification is sent from the server to the client when some long-running process is stopped.
		If client used `ProgressStart` to display an UI element, it can now hide it using the given `id`.
	**/
	static inline var ProgressStop = new NotificationType<{id:Int}>("haxe/progressStop");

	/**
		This notification is sent from the server to the client when the display port has changed.
	**/
	static inline var DidChangeDisplayPort = new NotificationType<{port:Int}>("haxe/didChangeDisplayPort");

	/**
		This notification is sent from the server to the client when a Haxe JSON-RPC method was executed.
	**/
	static inline var DidRunMethod = new NotificationType<MethodResult>("haxe/didRunHaxeMethod");

	/**
		This notification is sent from the server to the client when the request queue has changed.
	**/
	static inline var DidChangeRequestQueue = new NotificationType<{queue:Array<String>}>("haxe/didChangeRequestQueue");

	/**
		This notification is sent from the client to the server to instruct a specific Haxe JSON-RPC method to be executed.
	**/
	static inline var RunMethod = new RequestType<{method:String, ?params:Dynamic}, Dynamic, NoData>("haxe/runMethod");

	/**
		This notification is sent from the server to the client to indicate that it has failed to build a completion cache.
	**/
	static inline var CacheBuildFailed = new NotificationType<NoData>("haxe/cacheBuildFailed");

	/**
		This notification is sent from the server to the client to indicate that the Haxe process has crashed multiple times.
	**/
	static inline var HaxeKeepsCrashing = new NotificationType<NoData>("haxe/haxeKeepsCrashing");

	/**
		This notification is sent from the server to the client to indicate that an old Haxe version is being used.
	**/
	static inline var DidDetectOldHaxeVersion = new NotificationType<{haxe4Preview:Bool, version:String}>("haxe/didDetectOldHaxeVersion");
}

typedef MethodResult = {
	final kind:MethodResultKind;
	final method:String;
	final debugInfo:String;
	final response:Response<Dynamic>;
	final ?additionalTimes:AdditionalTimes;
}

enum abstract MethodResultKind(String) {
	var Haxe;
	var Lsp;
}

typedef AdditionalTimes = {
	final beforeCall:Float;
	final arrival:Float;
	final beforeProcessing:Float;
	final afterProcessing:Float;
}

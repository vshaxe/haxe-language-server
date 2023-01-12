package haxeLanguageServer;

import haxe.display.Protocol.Response;
import jsonrpc.Types;
import languageServerProtocol.textdocument.TextDocument;

/**
	Custom, Haxe-Language-Server-specific methods that are not part of the Language Server Protocol.
**/
@:publicFields
class LanguageServerMethods {
	/**
		This notification is sent from the client to the server when display arguments have changed.
	**/
	static inline final DidChangeDisplayArguments = new NotificationType<{arguments:Array<String>}>("haxe/didChangeDisplayArguments");

	/**
		This notification is sent from the client to the server when display arguments have changed.
	**/
	static inline final DidChangeDisplayServerConfig = new NotificationType<DisplayServerConfig>("haxe/didChangeDisplayServerConfig");

	/**
		This request is sent from the client to the server to determine the haxe package for a given file,
		based on class paths configuration.
	**/
	static inline final DeterminePackage = new RequestType<{fsPath:String}, {pack:String}, NoData>("haxe/determinePackage");

	/**
		This notification is sent from the client to the server to run a global diagnostics check.
	**/
	static inline final RunGlobalDiagnostics = new NotificationType<NoData>("haxe/runGlobalDiagnostics");

	/**
		This notification is sent from the server to the client when a global diagnostics check was finished successfully.
	**/
	static inline final DidRunRunGlobalDiagnostics = new NotificationType<NoData>("haxe/didRunGlobalDiagnostics");

	/**
		This notification is sent from the client to the server when the active text editor has changed.
	**/
	static inline final DidChangeActiveTextEditor = new NotificationType<{uri:DocumentUri}>("haxe/didChangeActiveTextEditor");

	/**
		This notification is sent from the server to the client when the display port has changed.
	**/
	static inline final DidChangeDisplayPort = new NotificationType<{port:Int}>("haxe/didChangeDisplayPort");

	/**
		This notification is sent from the server to the client when a Haxe JSON-RPC method was executed.
	**/
	static inline final DidRunMethod = new NotificationType<MethodResult>("haxe/didRunHaxeMethod");

	/**
		This notification is sent from the server to the client when the request queue has changed.
	**/
	static inline final DidChangeRequestQueue = new NotificationType<{queue:Array<String>}>("haxe/didChangeRequestQueue");

	/**
		This request is sent from the client to the server to instruct a specific Haxe JSON-RPC method to be executed.
	**/
	static inline final RunMethod = new RequestType<{method:String, ?params:Dynamic}, Dynamic, NoData>("haxe/runMethod");

	/**
		This notification is sent from the server to the client to indicate that it has failed to build a completion cache.
	**/
	static inline final CacheBuildFailed = new NotificationType<NoData>("haxe/cacheBuildFailed");

	/**
		This notification is sent from the server to the client to indicate that the Haxe process has crashed multiple times.
	**/
	static inline final HaxeKeepsCrashing = new NotificationType<NoData>("haxe/haxeKeepsCrashing");

	/**
		This notification is sent from the server to the client to indicate that an old Haxe version is being used.
	**/
	static inline final DidDetectOldHaxeVersion = new NotificationType<{haxe4Preview:Bool, version:String}>("haxe/didDetectOldHaxeVersion");

	/**
		This request is sent from the server to the client to get a list of available libraries.
	**/
	static inline final ListLibraries = new RequestType<Null<NoData>, Array<{name:String}>, NoData>("haxe/listLibraries");

	/**
		This request is sent from the client to the server to export current server recording.
	**/
	static inline final ExportServerRecording = new RequestType<Null<{dest:String}>, String, String>("haxe/exportServerRecording");
}

typedef MethodResult = {
	final kind:MethodResultKind;
	final method:String;
	final debugInfo:Null<String>;
	final response:Response<Dynamic>;
	final ?additionalTimes:AdditionalTimes;
}

enum abstract MethodResultKind(String) {
	final Haxe;
	final Lsp;
}

typedef AdditionalTimes = {
	final beforeCall:Float;
	final arrival:Float;
	final beforeProcessing:Float;
	final afterProcessing:Float;
}

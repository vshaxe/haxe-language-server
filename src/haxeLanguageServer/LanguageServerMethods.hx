package haxeLanguageServer;

import jsonrpc.Types;
import haxeLanguageServer.protocol.Protocol.Response;

/**
    Custom, Haxe-Language-Server-specific methods that are not part of the Language Server Protocol.
**/
@:publicFields
class LanguageServerMethods {
    /**
        This notification is sent from the client to the server when display arguments have changed.
    **/
    static inline var DidChangeDisplayArguments = new NotificationMethod<{arguments:Array<String>},NoData>("haxe/didChangeDisplayArguments");

    /**
        This notification is sent from the client to the server when display arguments have changed.
    **/
    static inline var DidChangeDisplayServerConfig = new NotificationMethod<DisplayServerConfig,NoData>("haxe/didChangeDisplayServerConfig");

    /**
        This request is sent from the client to the server to determine the haxe package for a given file,
        based on class paths configuration.
    **/
    static inline var DeterminePackage = new RequestMethod<{fsPath:String},{pack:String},NoData,NoData>("haxe/determinePackage");

    /**
        This notification is sent from the client to the server to run a global diagnostics check.
    **/
    static inline var RunGlobalDiagnostics = new NotificationMethod<NoData,NoData>("haxe/runGlobalDiagnostics");

    /**
        This notification is sent from the server to the client when a global diagnostics check was finished successfully.
    **/
    static inline var DidRunRunGlobalDiagnostics = new NotificationMethod<NoData,NoData>("haxe/didRunGlobalDiagnostics");

    /**
        This notification is sent from the client to the server when the active text editor has changed.
    **/
    static inline var DidChangeActiveTextEditor = new NotificationMethod<{uri:DocumentUri},NoData>("haxe/didChangeActiveTextEditor");

    /**
        This notification is sent from the server to the client when some long-running process is started.
        Client may display this somehow in the UI. The `id` is used later for sending `ProgressStop` notification.
    **/
    static inline var ProgressStart = new NotificationMethod<{id:Int, title:String},NoData>("haxe/progressStart");

    /**
        This notification is sent from the server to the client when some long-running process is stopped.
        If client used `ProgressStart` to display an UI element, it can now hide it using the given `id`.
    **/
    static inline var ProgressStop = new NotificationMethod<{id:Int},NoData>("haxe/progressStop");

    /**
        This notification is sent from the server to the client when the display port has changed.
    **/
    static inline var DidChangeDisplayPort = new NotificationMethod<{port:Int},NoData>("haxe/didChangeDisplayPort");

    /**
        This notification is sent from the server to the client when a Haxe JSON-RPC method was executed.
    **/
    static inline var DidRunHaxeMethod = new NotificationMethod<HaxeMethodResult,NoData>("haxe/didRunHaxeMethod");

    /**
        This notification is sent from the server to the client when the request queue has changed.
    **/
    static inline var DidChangeRequestQueue = new NotificationMethod<{queue:Array<String>},NoData>("haxe/didChangeRequestQueue");

    /**
        This notification is sent from the client to the server to instruct a specific Haxe JSON-RPC method to be executed.
    **/
    static inline var RunMethod = new NotificationMethod<{method:String, params:Any},NoData>("haxe/runMethod");

    /**
        This notification is sent from the server to the client to indicate that it has failed to build a completion cache.
    **/
    static inline var CacheBuildFailed = new NotificationMethod<NoData,NoData>("haxe/cacheBuildFailed");

    static inline var DocumentSymbols = new RequestMethod<DocumentSymbolParams,Array<DocumentSymbol>,NoData,TextDocumentRegistrationOptions>("haxe/documentSymbol");
}

typedef HaxeMethodResult = {
    final method:String;
    final debugInfo:String;
    final response:Response<Dynamic>;
    final ?additionalTimes:{
        final arrival:Float;
        final beforeProcessing:Float;
        final afterProcessing:Float;
    }
}

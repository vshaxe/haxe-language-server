package haxeLanguageServer;

import jsonrpc.Types;

@:publicFields
class VshaxeMethods {
    /**
        This notification is sent from the client to the server when display arguments have changed.
    **/
    static inline var DidChangeDisplayArguments = new NotificationMethod<{arguments:Array<String>}>("vshaxe/didChangeDisplayArguments");

    /**
        This notification is sent from the client to the server when display arguments have changed.
    **/
    static inline var DidChangeDisplayServerConfig = new NotificationMethod<DisplayServerConfig>("vshaxe/didChangeDisplayServerConfig");

    /**
        This request is sent from the client to the server to determine the haxe package for a given file,
        based on class paths configuration.
    **/
    static inline var DeterminePackage = new RequestMethod<{fsPath:String},{pack:String},NoData>("vshaxe/determinePackage");

    /**
        This notification is sent from the client to the server to run a global diagnostics check.
    **/
    static inline var RunGlobalDiagnostics = new NotificationMethod<NoData>("vshaxe/runGlobalDiagnostics");

    /**
        This notification is sent from the client to the server when the active text editor has changed.
    **/
    static inline var DidChangeActiveTextEditor = new NotificationMethod<{uri:DocumentUri}>("vshaxe/didChangeActiveTextEditor");

    /**
        This notification is sent from the server to the client to update the parse tree visualization.
    **/
    static inline var UpdateParseTree = new NotificationMethod<{uri:String, parseTree:String}>("vshaxe/updateParseTree");

    /**
        This notification is sent from the server to the client when some long-running process is started.
        Client may display this somehow in the UI. The `id` is used later for sending `ProgressStop` notification.
    **/
    static inline var ProgressStart = new NotificationMethod<{id:Int, title:String}>("vshaxe/progressStart");

    /**
        This notification is sent from the server to the client when some long-running process is stopped.
        If client used `ProgressStart` to display an UI element, it can now hide it using the given `id`.
    **/
    static inline var ProgressStop = new NotificationMethod<{id:Int}>("vshaxe/progressStop");

    /**
        This notification is sent from the server to the client when the display port has changed.
    **/
    static inline var DidChangeDisplayPort = new NotificationMethod<{port:Int}>("vshaxe/didChangeDisplayPort");
}

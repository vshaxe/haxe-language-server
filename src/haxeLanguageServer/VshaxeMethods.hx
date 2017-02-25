package haxeLanguageServer;

import jsonrpc.Types;

@:publicFields
class VshaxeMethods {
    /**
        This notification is sent from the client to the server when display arguments index is changed.
    **/
    static inline var DidChangeDisplayConfigurationIndex = new NotificationMethod<{index:Int}>("vshaxe/didChangeDisplayConfigurationIndex");

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
}

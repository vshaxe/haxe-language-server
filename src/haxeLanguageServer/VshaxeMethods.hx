package haxeLanguageServer;

import jsonrpc.Types;

@:publicFields
class VshaxeMethods {
    /**
        This notification is sent from the server to the client to ask the client to log a particular message in the vshaxe output channel.
    **/
    static inline var Log = new NotificationMethod<String>("vshaxe/log");

    /**
        This notification is sent from the client to the server when display arguments index is changed.
    **/
    static inline var DidChangeDisplayConfigurationIndex = new NotificationMethod<{index:Int}>("vshaxe/didChangeDisplayConfigurationIndex");

    /**
        This reuqest is sent from the client to the server to calculate the haxe package for a given file,
        based on class paths configuration.
    **/
    static inline var CalculatePackage = new RequestMethod<{fsPath:String},{pack:String},NoData>("vshaxe/calculatePackage");

    /**
        This notification is sent from the client to the server to run a global diagnostics check.
    **/
    static inline var RunGlobalDiagnostics = new NotificationMethod<String>("vshaxe/runGlobalDiagnostics");
}

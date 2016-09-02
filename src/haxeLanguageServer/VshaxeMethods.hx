package haxeLanguageServer;

import jsonrpc.Types;

@:publicFields
class VshaxeMethods {
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
    static inline var RunGlobalDiagnostics = new NotificationMethod<NoData>("vshaxe/runGlobalDiagnostics");
}

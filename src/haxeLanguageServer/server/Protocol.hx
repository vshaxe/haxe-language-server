package haxeLanguageServer.server;

import jsonrpc.Types;
import haxe.rtti.JsonModuleTypes;

// TODO: use URIs instead of fs paths?

/**
    Methods of the JSON-RPC-based `--display` protocol in Haxe 4.
**/
@:publicFields
class HaxeMethods {
    /**
        The initialize request is sent from the client to Haxe to determine the capabilities.
    **/
    static inline var Initialize = new HaxeRequestMethod<InitializeParams,InitializeResult>("initialize");

    /**
       Completion.
    **/
    static inline var Completion = new HaxeRequestMethod<CompletionParams,Array<CompletionItem<Dynamic>>>("textDocument/completion");

    /**
        The goto definition request is sent from the client to Haxe to resolve the definition location(s) of a symbol at a given text document position.
    **/
    static inline var GotoDefinition = new HaxeRequestMethod<PositionParams,Array<Location>>("textDocument/definition");

    /**
        The hover request is sent from the client to Haxe to request hover information at a given text document position.
    **/
    static inline var Hover = new HaxeRequestMethod<PositionParams,Null<HoverResult>>("textDocument/hover");

    /**
        This request is sent from the client to Haxe to determine the package for a given file, based on class paths configuration.
    **/
    static inline var DeterminePackage = new HaxeRequestMethod<FileParams,Array<String>>("textDocument/package");

    /*
        TODO:

        - finish completion
        - diagnostics
        - signature
        - codeLens
        - references
        - workspaceSymbols ("project/symbol"?)
        - documentSymbols ("textDocument/documentSymbol"?)
    */
}

/* Initialize */

typedef InitializeParams = {
    @:optional var logging:LoggingOptions;
}

typedef LoggingOptions = {
    @:optional var arguments:Bool;
    @:optional var cacheSignature:Bool;
    @:optional var cacheInvalidation:Bool;
    @:optional var completionResponse:Bool;
}

typedef HaxeCapabilities = {
    @:optional var hoverProvider:Bool;
    @:optional var definitionProvider:Bool;
    @:optional var completionProvider:Bool;
    @:optional var packageProvider:Bool;
}

typedef InitializeResult = {
    var capabilities:HaxeCapabilities;
}

/* Hover */

typedef HoverResult = {
    var range:Range;
    @:optional var documentation:String;
    @:optional var type:JsonType<Dynamic>;
}

/* Completion */

typedef CompletionParams = {
    > PositionParams,
    var wasAutoTriggered:Bool;
}

typedef HaxeTODO = Dynamic;

typedef Timer = {
    var name:String;
    var value:String;
}

enum abstract Literal(String) {
    var LNull = "null";
    var LTrue = "true";
    var LFalse = "false";
    var LThis = "this";
}

enum abstract CompletionItemKind<T>(String) {
    var CILocal = "Local";
    var CIMember:CompletionItemKind<JsonClassField> = "Member";
    var CIStatic:CompletionItemKind<JsonClassField> = "Static";
    var CIEnumField:CompletionItemKind<JsonEnumField> = "EnumField";
    var CIEnumAbstractField:CompletionItemKind<JsonClassField> = "EnumAbstractField";
    var CIGlobal = "Global";
    var CIType:CompletionItemKind<JsonModuleType<Dynamic>> = "Type";
    var CIPackage:CompletionItemKind<String> = "Package";
    var CIModule:CompletionItemKind<String> = "Module";
    var CILiteral:CompletionItemKind<Literal> = "Literal";
    var CITimer:CompletionItemKind<Timer> = "Timer";
    var CIMetadata:CompletionItemKind<JsonMetadataEntry> = "Metadata";
}

typedef CompletionItem<T> = {
    var kind:CompletionItemKind<T>;
    var args:T;
}

/* General types */

typedef FileParams = {
    var file:FsPath;
}

typedef PositionParams = {
    > FileParams,

    /**
        Unicode character offset in the file.
    **/
    var offset:Int;
}

typedef Location = {
    var file:FsPath;
    var range:Range;
}

typedef Range = languageServerProtocol.Types.Range;
typedef Position = languageServerProtocol.Types.Position;
typedef HaxeRequestMethod<TParams,TResponse> = RequestMethod<TParams,TResponse,NoData,NoData>;
typedef HaxeNotificationMethod<TParams> = NotificationMethod<TParams,NoData>;

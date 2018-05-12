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
    var Null = "null";
    var True = "true";
    var False = "false";
    var This = "this";
}

enum abstract CompletionItemKind<T>(String) {
    var Local = "Local";
    var Member:CompletionItemKind<JsonClassField> = "Member";
    var Static:CompletionItemKind<JsonClassField> = "Static";
    var EnumField:CompletionItemKind<JsonEnumField> = "EnumField";
    var EnumAbstractField:CompletionItemKind<JsonClassField> = "EnumAbstractField";
    var Global = "Global";
    var Type:CompletionItemKind<JsonModuleType<Dynamic>> = "Type";
    var Package:CompletionItemKind<String> = "Package";
    var Module:CompletionItemKind<String> = "Module";
    var Literal:CompletionItemKind<Literal> = "Literal";
    var Timer:CompletionItemKind<Timer> = "Timer";
    var Metadata:CompletionItemKind<JsonMetadataEntry> = "Metadata";
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

package haxeLanguageServer.server;

import jsonrpc.Types;
import haxe.rtti.JsonModuleTypes;
import languageServerProtocol.Types.CompletionItemKind as VSCodeCompletionItemKind;

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
    static inline var Completion = new HaxeRequestMethod<CompletionParams,CompletionResult>("textDocument/completion");

    /**
        The goto definition request is sent from the client to Haxe to resolve the definition location(s) of a symbol at a given text document position.
    **/
    static inline var GotoDefinition = new HaxeRequestMethod<PositionParams,GotoDefinitionResult>("textDocument/definition");

    /**
        The hover request is sent from the client to Haxe to request hover information at a given text document position.
    **/
    static inline var Hover = new HaxeRequestMethod<PositionParams,HoverResult>("textDocument/hover");

    /**
        This request is sent from the client to Haxe to determine the package for a given file, based on class paths configuration.
    **/
    static inline var DeterminePackage = new HaxeRequestMethod<FileParams,DeterminePackageResult>("textDocument/package");

    /**
        Signature.
    **/
    static inline var SignatureHelp = new HaxeRequestMethod<CompletionParams,SignatureResult>("textDocument/signatureHelp");

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

typedef Timer = {
    final name:String;
    final path:String;
    final info:String;
    final time:Float;
    final calls:Int;
    final percentTotal:Float;
    final percentParent:Float;
    @:optional final children:Array<Timer>;
}

typedef Response<T> = {
    final result:T;
    /** Only sent if `--times` is enabled. **/
    @:optional final timers:Timer;
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
    @:optional var signatureHelpProvider:Bool;
}

typedef InitializeResult = Response<{
    var capabilities:HaxeCapabilities;
}>;

/* Completion */

typedef CompletionParams = {
    > PositionParams,
    var wasAutoTriggered:Bool;
}

typedef Global<T> = {
    var modulePath:JsonPath;
    var name:String;
    var type:JsonType<T>;
}

enum abstract Literal(String) {
    var Null = "null";
    var True = "true";
    var False = "false";
    var This = "this";
}

typedef CompletionType = {
    var path:JsonPath;
    var kind:VSCodeCompletionItemKind;
}

extern enum abstract ModuleTypeKind(Int) {
    var Class = 0;
    var Interface = 1;
    var Enum = 2;
    var Abstract = 3;
    var EnumAbstract = 4;
    var TypeAlias = 5;
    var Struct = 6;
}

typedef ModuleType = {
    var pack:Array<String>;
    var name:String;
    var module:String;
    var pos:JsonPos;
    var isPrivate:Bool;
    var params:JsonTypeParameters;
    var meta:JsonMetadata;
    var doc:JsonDoc;
    var isExtern:Bool;
    var kind:ModuleTypeKind;
}

enum abstract CompletionItemKind<T>(String) {
    var Local = "Local";
    var Member:CompletionItemKind<JsonClassField> = "Member";
    var Static:CompletionItemKind<JsonClassField> = "Static";
    var EnumField:CompletionItemKind<JsonEnumField> = "EnumField";
    var EnumAbstractField:CompletionItemKind<JsonClassField> = "EnumAbstractField";
    var Global:CompletionItemKind<Global<Dynamic>> = "Global";
    var Type:CompletionItemKind<CompletionType> = "Type";
    var Package:CompletionItemKind<String> = "Package";
    var Module:CompletionItemKind<String> = "Module";
    var Literal:CompletionItemKind<Literal> = "Literal";
    var Metadata:CompletionItemKind<JsonMetadataEntry> = "Metadata";
}

typedef CompletionItem<T> = {
    var kind:CompletionItemKind<T>;
    var args:T;
}

enum abstract CompletionResultKind(Int) {
    var Field = 0;
    var StructureField = 1;
    var Toplevel = 2;
    var Metadata = 3;
}

typedef CompletionResponse<T> = {
    var items:Array<CompletionItem<T>>;
    var kind:CompletionResultKind;
    var sorted:Bool;
    @:optional var replaceRange:Range;
}

typedef CompletionResult = Response<CompletionResponse<Dynamic>>;

/* GotoDefinition */

typedef GotoDefinitionResult = Response<Array<Location>>;

/* Hover */

typedef HoverResult = Response<Null<{
    var range:Range;
    @:optional var documentation:String;
    @:optional var type:JsonType<Dynamic>;
}>>;

/* DeterminePackage */

typedef DeterminePackageResult = Response<Array<String>>;

/* Signature */

typedef SignatureInformation = {
    > JsonFunctionSignature,
    @:optional var documentation:String;
}

typedef SignatureItem = {
    var signatures:Array<SignatureInformation>;
    var activeSignature:Int;
    var activeParameter:Int;
}

typedef SignatureResult = Response<SignatureItem>;

/* General types */

typedef FileParams = {
    var file:FsPath;
}

typedef PositionParams = {
    > FileParams,
    /** Unicode character offset in the file. **/
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

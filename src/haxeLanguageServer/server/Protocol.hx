package haxeLanguageServer.server;

import jsonrpc.Types;
import haxe.display.JsonModuleTypes;

/**
    Methods of the JSON-RPC-based `--display` protocol in Haxe 4.
    A lot of the methods are *inspired* by the Language Server Protocol, but there is **no** intention to be directly compatible with it.
**/
@:publicFields
class HaxeMethods {
    /**
        The initialize request is sent from the client to Haxe to determine the capabilities.
    **/
    static inline var Initialize = new HaxeRequestMethod<InitializeParams,InitializeResult>("initialize");

    /**
        The completion request is sent from the client to Haxe to request code completion.
        Haxe automatically determines the type of completion to use based on the passed position, see `CompletionResultKind`.
    **/
    static inline var Completion = new HaxeRequestMethod<CompletionParams,CompletionResult>("textDocument/completion");

    /**
        The request is sent from the client to Haxe to resolve additional information for a given completion item.
    **/
    static inline var CompletionItemResolve = new HaxeRequestMethod<CompletionItemResolveParams,CompletionItemResolveResult>("completionItem/resolve");

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
        The signature help request is sent from the client to Haxe to request signature information at a given cursor position.
    **/
    static inline var SignatureHelp = new HaxeRequestMethod<CompletionParams,SignatureHelpResult>("textDocument/signatureHelp");

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

    /* Server */

    /**
        This request is sent from the client to Haxe to explore the class paths. This effectively creates a cache for toplevel completion.
    **/
    static inline var ReadClassPaths = new HaxeRequestMethod<NoData,Response<NoData>>("server/readClassPaths");
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
    @:optional var supportsResolve:Bool;
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

enum abstract ModuleTypeKind(Int) {
    var Class = 0;
    var Interface = 1;
    var Enum = 2;
    var Abstract = 3;
    var EnumAbstract = 4;
    /** A `typedef` that is just an alias for another type. **/
    var TypeAlias = 5;
    /** A `typedef` that is an alias for an anonymous structure. **/
    var Struct = 6;
}

enum abstract ImportStatus(Int) {
    /**
        This type is already available with it's unqualified name for one of these reasons:
          - it's a toplevel type
          - it's imported with an `import` in the current module
          - it's imported in an `import.hx` file
    **/
    var Imported = 0;

    /**
        The type is currently not imported. It can be accessed either
        with its fully qualified name or by inserting an import.
    **/
    var Unimported = 1;

    /**
        A type with the same name is already imported in the module.
        The fully qualified name has to be used to access it.
    **/
    var Shadowed = 2;
}

typedef ModuleType = {
    >JsonPath,
    var moduleName:String;
    var pos:JsonPos;
    var isPrivate:Bool;
    var params:Array<ModuleTypeParameter>;
    var meta:JsonMetadata;
    var doc:JsonDoc;
    var isExtern:Bool;
    var kind:ModuleTypeKind;
    var importStatus:ImportStatus;
}

typedef ModuleTypeParameter = {
    var name:String;
    var meta:JsonMetadata;
}

typedef Literally<T> = {
    var name:String;
    var type:JsonType<T>;
}

enum abstract MetadataUsage(String) {
    var Class = "TClass";
    var ClassField = "ClassField";
    var Abstract = "TAbstract";
    var AbstractField = "TAbstractField";
    var Enum = "TEnum";
    var Typedef = "TTypedef";
    var AnyField = "TAnyField";
    var Expr = "TExpr";
    var TypeParameter = "TTypeParameter";
}

enum abstract Platform(String) {
    var Cross = "Cross";
    var Js = "Js";
    var Lua = "Lua";
    var Neko = "Neko";
    var Flash = "Flash";
    var Php = "Php";
    var Cpp = "Cpp";
    var Cs = "Cs";
    var Java = "Java";
    var Python = "Python";
    var Hl = "Hl";
    var Eval = "Eval";
}

enum abstract MetadataParameterKind<T>(String) {
    var HasParam:MetadataParameterKind<String> = "HasParam";
    var Platform:MetadataParameterKind<Platform> = "Platform";
    var Platforms:MetadataParameterKind<Array<Platform>> = "Platforms";
    var UsedOn:MetadataParameterKind<MetadataUsage> = "UsedOn";
    var UsedOnEither:MetadataParameterKind<Array<MetadataUsage>> = "UsedOnEither";
}

typedef MetadataParameter<T> = {
    var kind:MetadataParameterKind<T>;
    var args:T;
}

typedef Metadata<T> = {
    var name:String;
    var doc:JsonDoc;
    var parameters:Array<MetadataParameter<T>>;
}

typedef Keyword = {
    var name:String;
}

enum abstract CompletionItemKind<T>(String) {
    var Local = "Local";
    var Member:CompletionItemKind<JsonClassField> = "Member";
    var Static:CompletionItemKind<JsonClassField> = "Static";
    var EnumField:CompletionItemKind<JsonEnumField> = "EnumField";
    var EnumAbstractField:CompletionItemKind<JsonClassField> = "EnumAbstractField";
    var Global:CompletionItemKind<Global<Dynamic>> = "Global";
    var Type:CompletionItemKind<ModuleType> = "Type";
    var Package:CompletionItemKind<String> = "Package";
    var Module:CompletionItemKind<String> = "Module";
    var Literal:CompletionItemKind<Literally<Dynamic>> = "Literal";
    var Metadata:CompletionItemKind<JsonMetadataEntry> = "Metadata";
    var Keyword:CompletionItemKind<Keyword> = "Keyword";
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
    var TypeHint = 4;
    var Extends = 5;
    var Implements = 6;
    var StructExtension = 7;
    var Import = 8;
    var Using = 9;
    var New = 10;
}

typedef CompletionResponse<T> = {
    var items:Array<CompletionItem<T>>;
    var kind:CompletionResultKind;
    var sorted:Bool;
    @:optional var replaceRange:Range;
}

typedef CompletionResult = Response<CompletionResponse<Dynamic>>;

/* CompletionItem Resolve */

typedef CompletionItemResolveParams = {
    var index:Int;
};

typedef CompletionItemResolveResult = Response<{
    var item:CompletionItem<Dynamic>;
}>;

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

typedef SignatureHelpResult = Response<SignatureItem>;

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

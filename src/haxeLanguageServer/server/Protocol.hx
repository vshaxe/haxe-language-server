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
    static inline var Completion = new HaxeRequestMethod<CompletionParams,CompletionResult>("display/completion");

    /**
        The request is sent from the client to Haxe to resolve additional information for a given completion item.
    **/
    static inline var CompletionItemResolve = new HaxeRequestMethod<CompletionItemResolveParams,CompletionItemResolveResult>("display/completionItem/resolve");

    /**
        The goto definition request is sent from the client to Haxe to resolve the definition location(s) of a symbol at a given text document position.
    **/
    static inline var GotoDefinition = new HaxeRequestMethod<PositionParams,GotoDefinitionResult>("display/definition");

    /**
        The hover request is sent from the client to Haxe to request hover information at a given text document position.
    **/
    static inline var Hover = new HaxeRequestMethod<PositionParams,HoverResult>("display/hover");

    /**
        This request is sent from the client to Haxe to determine the package for a given file, based on class paths configuration.
    **/
    static inline var DeterminePackage = new HaxeRequestMethod<FileParams,DeterminePackageResult>("display/package");

    /**
        The signature help request is sent from the client to Haxe to request signature information at a given cursor position.
    **/
    static inline var SignatureHelp = new HaxeRequestMethod<CompletionParams,SignatureHelpResult>("display/signatureHelp");

    /*
        TODO:

        - finish completion
        - diagnostics
        - signature
        - codeLens
        - references
        - workspaceSymbols ("project/symbol"?)
        - documentSymbols ("display/documentSymbol"?)
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
    /** UNIX timestamp at the moment the data was sent. **/
    final timestamp:Float;
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
    @:optional var completionResolveProvider:Bool;
}

typedef InitializeResult = Response<{
    var capabilities:HaxeCapabilities;
}>;

/* Completion */

typedef CompletionParams = {
    >PositionParams,
    var wasAutoTriggered:Bool;
}

typedef FieldResolution = {
    /**
        Whether it's valid to use the unqualified name of the field or not.
        This is `false` if the identifier is shadowed.
    **/
    var isQualified:Bool;

    /**
        The qualifier that has to be inserted to use the field if `!isQualified`.
        Can either be `this` for instance fields for the type name for `static` fields.
    **/
    var qualifier:String;
}

typedef JsonLocal<T> = {
    var id:Int;
    var name:String;
    var type:JsonType<T>;
    var kind:LocalKind;
    @:optional var extra:{
        var params:Array<JsonTypeParameter>;
        var expr:JsonExpr;
    };
    var meta:JsonMetadata;
    var pos:JsonPos;
}

enum abstract LocalKind(Int) {
    var Variable = 0;
    var Argument = 1;
    var Iterator = 2;
    var CaptureVariable = 3;
    var CatchVariable = 4;
    var LocalFunction = 5;
}

enum abstract ClassFieldOriginKind<T>(Int) {
    /**
        The field is declared on the current type itself.
    **/
    var Self:ClassFieldOriginKind<JsonModuleType<T>> = 0;

    /**
        The field is a static field brought into context via a static import
        (`import pack.Module.Type.field`).
    **/
    var StaticImport:ClassFieldOriginKind<JsonModuleType<T>> = 1;

    /**
        The field is declared on a parent type, such as:
        - a super class field that is not overriden
        - a forwarded abstract field
    **/
    var Parent:ClassFieldOriginKind<JsonModuleType<T>> = 2;

    /**
        The field is a static extension method brought
        into context with the `using` keyword.
    **/
    var StaticExtension:ClassFieldOriginKind<JsonModuleType<T>> = 3;

    /**
        This field doesn't belong to any named type, just an anonymous structure.
    **/
    var AnonymousStructure:ClassFieldOriginKind<JsonAnon> = 4;

    /**
        Special fields built into the compiler, such as:
        - `code` on single-character Strings
        - `bind()` on functions.
    **/
    var BuiltIn:ClassFieldOriginKind<NoData> = 5;
}

typedef ClassFieldOrigin<T> = {
    var kind:ClassFieldOriginKind<T>;
    @:optional var args:T;
}

typedef ClassFieldUsage<T> = {
    var field:JsonClassField;
    var resolution:FieldResolution;
    @:optional var origin:ClassFieldOrigin<T>;
}

enum abstract EnumValueOriginKind<T>(Int) {
    /**
        The enum value is declared on the current type itself.
    **/
    var Self:EnumValueOriginKind<JsonModuleType<T>> = 0;

    /**
        The enum value is brought into context via a static import
        (`import pack.Module.Enum.Value`).
    **/
    var StaticImport:EnumValueOriginKind<JsonModuleType<T>> = 1;
}

typedef EnumValueOrigin<T> = {
    var kind:EnumValueOriginKind<T>;
    @:optional var args:T;
}

typedef EnumValueUsage<T> = {
    var field:JsonEnumField;
    var resolution:FieldResolution;
    @:optional var origin:EnumValueOrigin<T>;
}

enum abstract Literal(String) {
    var Null = "null";
    var True = "true";
    var False = "false";
    var This = "this";
    var Trace = "trace";
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
    /** A type name introduced by `import as` / `import in` **/
    var ImportAlias = 7;
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
    var unifiesWithIterable:Bool;
}

typedef JsonType<T> = {
    >haxe.display.JsonModuleTypes.JsonType<T>,
    var unifiesWithIterable:Bool; // TODO: move to JsonModuleTypes?
}

typedef ModuleTypeParameter = {
    var name:String;
    var meta:JsonMetadata;
}

typedef JsonLiteral<T> = {
    var name:String;
    var type:JsonType<T>;
}

enum abstract MetadataTarget(String) {
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

typedef Metadata = {
    var name:String;
    var doc:JsonDoc;
    var parameters:Array<String>;
    var platforms:Array<Platform>;
    var target:Array<MetadataTarget>;
}

typedef Keyword = {
    var name:KeywordKind;
}

enum abstract KeywordKind(String) to String {
    var Implements = "implements";
    var Extends = "extends";
    var Function = "function";
    var Var = "var";
    var If = "if";
    var Else = "else";
    var While = "while";
    var Do = "do";
    var For = "for";
    var Break = "break";
    var Return = "return";
    var Continue = "continue";
    var Switch = "switch";
    var Case = "case";
    var Default = "default";
    var Try = "try";
    var Catch = "catch";
    var New = "new";
    var Throw = "throw";
    var Untyped = "untyped";
    var Cast = "cast";
    var Macro = "macro";
}

enum abstract PackageContentKind(Int) {
    var Module = 0;
    var Package = 1;
}

typedef Package = {
    var name:String;
    @:optional var contents:Array<{name:String, kind:PackageContentKind}>;
}

typedef Module = {
    var name:String;
    @:optional var contents:Array<ModuleType>;
}

enum abstract CompletionItemKind<T>(String) {
    var Local:CompletionItemKind<JsonLocal<Dynamic>> = "Local";
    var ClassField:CompletionItemKind<ClassFieldUsage<Dynamic>> = "ClassField";
    var EnumValue:CompletionItemKind<EnumValueUsage<Dynamic>> = "EnumField";
    var EnumAbstractValue:CompletionItemKind<ClassFieldUsage<Dynamic>> = "EnumAbstractField";
    var Type:CompletionItemKind<ModuleType> = "Type";
    var Package:CompletionItemKind<Package> = "Package";
    var Module:CompletionItemKind<Module> = "Module";
    var Literal:CompletionItemKind<JsonLiteral<Dynamic>> = "Literal";
    var Metadata:CompletionItemKind<Metadata> = "Metadata";
    var Keyword:CompletionItemKind<Keyword> = "Keyword";
    var AnonymousStructure:CompletionItemKind<JsonAnon> = "AnonymousStructure";
    var Expression:CompletionItemKind<JsonTExpr> = "Expression";
}

typedef CompletionItem<T> = {
    var kind:CompletionItemKind<T>;
    var args:T;
}

enum abstract CompletionModeKind<T>(Int) {
    var Field:CompletionModeKind<CompletionItem<Dynamic>> = 0;
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
    var Pattern = 11;
    var Override = 12;
    var TypeRelation = 13;
}

typedef CompletionMode<T> = {
    var kind:CompletionModeKind<T>;
    @:optional var args:T;
}

typedef CompletionResponse<T1, T2> = {
    var items:Array<CompletionItem<T1>>;
    var kind:CompletionModeKind<Dynamic>; // TODO: remove kind once mode is added
    var mode:CompletionMode<T2>;
    var sorted:Bool;
    @:optional var replaceRange:Range;
}

typedef CompletionResult = Response<CompletionResponse<Dynamic,Dynamic>>;

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
    @:optional var contents:String;
}

typedef Location = {
    var file:FsPath;
    var range:Range;
}

typedef Range = languageServerProtocol.Types.Range;
typedef Position = languageServerProtocol.Types.Position;
typedef HaxeRequestMethod<TParams,TResponse> = RequestMethod<TParams,TResponse,NoData,NoData>;
typedef HaxeNotificationMethod<TParams> = NotificationMethod<TParams,NoData>;

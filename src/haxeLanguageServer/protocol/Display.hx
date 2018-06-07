package haxeLanguageServer.protocol;

import jsonrpc.Types.NoData;
import haxe.display.JsonModuleTypes;
import haxeLanguageServer.protocol.Protocol;

/**
    Methods of the JSON-RPC-based `--display` protocol in Haxe 4.
    A lot of the methods are *inspired* by the Language Server Protocol, but there is **no** intention to be directly compatible with it.
**/
@:publicFields
class DisplayMethods {
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
        The find references request is sent from the client to Haxe to find locations that reference the symbol at a given text document position.
    **/
    static inline var FindReferences = new HaxeRequestMethod<PositionParams,GotoDefinitionResult>("display/findReferences");

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
}

enum abstract CompilerMetadata(String) {
    var Op = ":op";
    var Resolve = ":resolve";
    var ArrayAccess = ":arrayAccess";
    var Final = ":final";
    var Optional = ":optional";
    // TODO
}

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
        Can either be `this` or `super` for instance fields for the type name for `static` fields.
    **/
    var qualifier:String;
}

typedef JsonLocal<T> = {
    var id:Int;
    var name:String;
    var type:JsonType<T>;
    var origin:LocalOrigin;
    var capture:Bool;
    @:optional var extra:{
        var params:Array<JsonTypeParameter>;
        var expr:JsonExpr;
    };
    var meta:JsonMetadata;
    var pos:JsonPos;
}

enum abstract LocalOrigin(Int) {
    var LocalVariable = 0;
    var Argument = 1;
    var ForVariable = 2;
    var PatternVariable = 3;
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

    /**
        The origin of this class field is unknown.
    **/
    var Unknown:ClassFieldOriginKind<NoData> = 6;
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
    //var ImportAlias = 7;
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
    var constraints:Array<JsonType<Dynamic>>;
}

typedef JsonLiteral<T> = {
    var name:String;
}

/* enum abstract MetadataTarget(String) {
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
} */

typedef Metadata = {
    var name:String;
    var doc:JsonDoc;
    /* var parameters:Array<String>;
    var platforms:Array<Platform>;
    var target:Array<MetadataTarget>; */
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

/* enum abstract PackageContentKind(Int) {
    var Module = 0;
    var Package = 1;
} */

typedef Package = {
    var path:JsonPath;
    // @:optional var contents:Array<{name:String, kind:PackageContentKind}>;
}

typedef Module = {
    var path:JsonPath;
    // @:optional var contents:Array<ModuleType>;
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
    var TypeParameter:CompletionItemKind<ModuleTypeParameter> = "TypeParameter";
}

typedef CompletionItem<T> = {
    var kind:CompletionItemKind<T>;
    var args:T;
    @:optional var type:JsonType<Dynamic>;
}

// rename all "Usage" stuff to "Occurence"?
typedef CompletionItemUsage<T> = {
    var range:Range;
    var item:CompletionItem<T>;
    @:optional var moduleType:JsonModuleType<Dynamic>;
}

typedef FieldCompletionSubject<T> = {
    >CompletionItemUsage<T>,
    // var isIterable:Bool; TODO
}

typedef ToplevelCompletion<T> = {
    @:optional var expectedType:JsonType<T>;
    @:optional var expectedTypeFollowed:JsonType<T>;
}

enum abstract CompletionModeKind<T>(Int) {
    var Field:CompletionModeKind<FieldCompletionSubject<Dynamic>> = 0;
    var StructureField = 1;
    var Toplevel:CompletionModeKind<ToplevelCompletion<Dynamic>> = 2;
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
    var mode:CompletionMode<T2>;
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

typedef HoverResult = Response<CompletionItemUsage<Dynamic>>;

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

typedef Range = haxe.display.Position.Range;
typedef Position = haxe.display.Position.Position;

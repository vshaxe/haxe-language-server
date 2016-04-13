import haxe.extern.EitherType;

import BasicTypes;

/**
    Helper type for the `MethodName` values.
    Represents that value of this type is a request.
**/
abstract Request<TParams,TResponse,TError>(String) to String {}

/**
    Helper type for the `MethodName` values.
    Represents that value of this type is a notification.
**/
abstract Notification<TParams>(String) to String {}

/**
    Method names for the protocol requests and notifications.
    Each value must be typed as either `Request` or `Notification.
**/
@:enum abstract MethodName<TParams,TResponse,TError>(String) to String from Request<TParams,TResponse,TError> from Notification<TParams> {
    /**
        The initialize request is sent as the first request from the client to the server.
    **/
    var Initialize : Request<InitializeParams,InitializeResult,InitializeError> = "initialize";

    /**
        The shutdown request is sent from the client to the server.
        It asks the server to shutdown, but to not exit (otherwise the response might not be delivered correctly to the client).
        There is a separate exit notification that asks the server to exit.
    **/
    var Shutdown : Notification<Void> = "shutdown";

    /**
        A notification to ask the server to exit its process.
    **/
    var Exit : Notification<Void> = "exit";

    /**
        The show message notification is sent from a server to a client to ask the client to display a particular message in the user interface.
    **/
    var ShowMessage : Notification<ShowMessageParams> = "window/showMessage";

    /**
        The log message notification is send from the server to the client to ask the client to log a particular message.
    **/
    var LogMessage : Notification<LogMessageParams> = "window/logMessage";

    /**
        A notification send from the client to the server to signal the change of configuration settings.
    **/
    var DidChangeConfiguration : Notification<DidChangeConfigurationParams> = "workspace/didChangeConfiguration";

    /**
        The document open notification is sent from the client to the server to signal newly opened text documents.
        The document's truth is now managed by the client and the server must not try to read the document's truth using the document's uri.
    **/
    var DidOpenTextDocument : Notification<DidOpenTextDocumentParams> = "textDocument/didOpen";

    /**
        The document change notification is sent from the client to the server to signal changes to a text document.
    **/
    var DidChangeTextDocument : Notification<DidChangeTextDocumentParams> = "textDocument/didChange";

    /**
        The document close notification is sent from the client to the server when the document got closed in the client.
        The document's truth now exists where the document's uri points to (e.g. if the document's uri is a file uri the truth now exists on disk).
    **/
    var DidCloseTextDocument : Notification<DidCloseTextDocumentParams> = "textDocument/didClose";

    /**
        The document save notification is sent from the client to the server when the document for saved in the clinet.
    **/
    var DidSaveTextDocument : Notification<DidCloseTextDocumentParams> = "textDocument/didSave";

    /**
        The watched files notification is sent from the client to the server when the client detects changes to file watched by the lanaguage client.
    **/
    var DidChangeWatchedFiles : Notification<DidChangeWatchedFilesParams> = "workspace/didChangeWatchedFiles";

    /**
        Diagnostics notification are sent from the server to the client to signal results of validation runs.
    **/
    var PublishDiagnostics : Notification<PublishDiagnosticsParams> = "textDocument/publishDiagnostics";

    /**
        The Completion request is sent from the client to the server to compute completion items at a given cursor position.
        Completion items are presented in the IntelliSense user interface.
        If computing complete completion items is expensive servers can additional provide a handler for the resolve completion item request.
        This request is send when a completion item is selected in the user interface.
    **/
    var Completion : Request<TextDocumentPositionParams,Array<CompletionItem>,Void> = "textDocument/completion";

    /**
        The request is sent from the client to the server to resolve additional information for a given completion item.
    **/
    var CompletionItemResolve : Request<CompletionItem,CompletionItem,Void> = "completionItem/resolve";

    /**
        The hover request is sent from the client to the server to request hover information at a given text document position.
    **/
    var Hover : Request<TextDocumentPositionParams,Hover,Void> = "textDocument/hover";

    /**
        The signature help request is sent from the client to the server to request signature information at a given cursor position.
    **/
    var SignatureHelp : Request<TextDocumentPositionParams,SignatureHelp,Void> = "textDocument/signatureHelp";

    /**
        The goto definition request is sent from the client to the server to to resolve the defintion location of a symbol at a given text document position.
    **/
    var GotoDefinition : Request<TextDocumentPositionParams,EitherType<Location,Array<Location>>,Void> = "textDocument/definition";

    /**
        The references request is sent from the client to the server to resolve project-wide references for the symbol denoted by the given text document position.
    **/
    var FindReferences : Request<ReferenceParams,Array<Location>,Void> = "textDocument/references";

    /**
        The document highlight request is sent from the client to the server to to resolve a document highlights for a given text document position.
    **/
    var DocumentHighlights : Request<TextDocumentPositionParams,DocumentHighlight,Void> = "textDocument/documentHighlight";

    /**
        The document symbol request is sent from the client to the server to list all symbols found in a given text document.
    **/
    var DocumentSymbols : Request<DocumentSymbolParams,Array<SymbolInformation>,Void> = "textDocument/documentSymbol";

    /**
        The workspace symbol request is sent from the client to the server to list project-wide symbols matching the query string.
    **/
    var WorkspaceSymbols : Request<WorkspaceSymbolParams,Array<SymbolInformation>,Void> = "workspace/symbol";

    /**
        The code action request is sent from the client to the server to compute commands for a given text document and range.
        The request is trigger when the user moves the cursor into an problem marker in the editor or presses the lightbulb associated with a marker.
    **/
    var CodeAction : Request<CodeActionParams,Array<Command>,Void> = "textDocument/codeAction";

    /**
        The code lens request is sent from the client to the server to compute code lenses for a given text document.
    **/
    var CodeLens : Request<CodeLensParams,Array<CodeLens>,Void> = "textDocument/codeLens";

    /**
        The code lens resolve request is sent from the clien to the server to resolve the command for a given code lens item.
    **/
    var CodeLensResolve : Request<CodeLens,CodeLens,Void> = "codeLens/resolve";

    /**
        The document formatting resquest is sent from the server to the client to format a whole document.
    **/
    var DocumentFormatting : Request<DocumentFormattingParams,Array<TextEdit>,Void> = "textDocument/formatting";

    /**
        The document range formatting request is sent from the client to the server to format a given range in a document.
    **/
    var DocumentOnTypeFormatting : Request<DocumentOnTypeFormattingParams,Array<TextEdit>,Void> = "textDocument/onTypeFormatting";

    /**
        The document on type formatting request is sent from the client to the server to format parts of the document during typing.
    **/
    var Rename : Request<RenameParams,WorkspaceEdit,Void> = "textDocument/rename";    
}

typedef InitializeParams = {
    var processId:Int;
    var rootPath:Null<String>;
    var capabilities:ClientCapabilities;
}

typedef InitializeResult = {
    var capabilities:ServerCapabilities;
}

typedef InitializeError = {
    var retry:Bool;
}

typedef ClientCapabilities = {} // unspecified

@:enum abstract TextDocumentSyncKind(Int) {
    var None = 0;
    var Full = 1;
    var Incremental = 2;
}

typedef CompletionOptions = {
    @:optional var resolveProvider:Bool;
    @:optional var triggerCharacters:Array<String>;
}

typedef SignatureHelpOptions = {
    @:optional var triggerCharacters:Array<String>;
}

typedef CodeLensOptions = {
    @:optional var resolveProvider:Bool;
}

typedef DocumentOnTypeFormattingOptions = {
    var firstTriggerCharacter:String;
    @:optional var moreTriggerCharacter:Array<String>;
}

typedef ServerCapabilities = {
    @:optional var textDocumentSync:TextDocumentSyncKind;
    @:optional var hoverProvider:Bool;
    @:optional var completionProvider:CompletionOptions;
    @:optional var signatureHelpProvider:SignatureHelpOptions;
    @:optional var definitionProvider:Bool;
    @:optional var referencesProvider:Bool;
    @:optional var documentHighlightProvider:Bool;
    @:optional var documentSymbolProvider:Bool;
    @:optional var workspaceSymbolProvider:Bool;
    @:optional var codeActionProvider:Bool;
    @:optional var codeLensProvider:CodeLensOptions;
    @:optional var documentFormattingProvider:Bool;
    @:optional var documentRangeFormattingProvider:Bool;
    @:optional var documentOnTypeFormattingProvider:DocumentOnTypeFormattingOptions;
    @:optional var renameProvider:Bool;
}

typedef ShowMessageParams = {
    var type:MessageType;
    var message:String;
}

@:enum abstract MessageType(Int) to Int {
    var Error = 1;
    var Warning = 2;
    var Info = 3;
    var Log = 4;
}

typedef LogMessageParams = {
    var type:MessageType;
    var message:String;
}

typedef DidChangeConfigurationParams = {
    var settings:Dynamic;
}

typedef DidOpenTextDocumentParams = {
    >TextDocumentIdentifier,
    var textDocument:TextDocumentItem;
}

typedef DidChangeTextDocumentParams = {
    var textDocument:VersionedTextDocumentIdentifier;
    var contentChanges:Array<TextDocumentContentChangeEvent>;
}

typedef TextDocumentContentChangeEvent = {
    @:optional var range:Range;
    @:optional var rangeLength:Int;
    var text:String;
}

typedef DidCloseTextDocumentParams = {
    var textDocument:TextDocumentIdentifier;
}

typedef DidSaveTextDocumentParams = {
    var textDocument:TextDocumentIdentifier;
}

typedef DidChangeWatchedFilesParams = {
    var changes:Array<FileEvent>;
}

@:enum abstract FileChangeType(Int) to Int {
    var Created = 1;
    var Changed = 2;
    var Deleted = 3;
}

typedef FileEvent = {
    var uri:String;
    var type:FileChangeType;
}

typedef PublishDiagnosticsParams = {
    var uri:String;
    var diagnostics:Array<Diagnostic>;
}

typedef CompletionItem = {
    var label:String;
    @:optional var kind:CompletionItemKind;
    @:optional var detail:String;
    @:optional var documentation:String;
    @:optional var sortText:String;
    @:optional var filterText:String;
    @:optional var insertText:String;
    @:optional var textEdit:TextEdit;
    @:optional var data:Dynamic;
}

@:enum abstract CompletionItemKind(Int) to Int {
    var Text = 1;
    var Method = 2;
    var Function = 3;
    var Constructor = 4;
    var Field = 5;
    var Variable = 6;
    var Class = 7;
    var Interface = 8;
    var Module = 9;
    var Property = 10;
    var Unit = 11;
    var Value = 12;
    var Enum = 13;
    var Keyword = 14;
    var Snippet = 15;
    var Color = 16;
    var File = 17;
    var Reference = 18;
}

typedef MarkedString = EitherType<String,{language:String, value:String}>;

typedef Hover = {
    var contents:EitherType<MarkedString,Array<MarkedString>>;
    @:optional var range:Range;
}

typedef SignatureHelp = {
    var signatures:Array<SignatureInformation>;
    @:optional var activeSignature:Int;
    @:optional var activeParameter:Int;
}

typedef SignatureInformation = {
    var label:String;
    @:optional var documentation:String;
    @:optional var parameters:Array<ParameterInformation>;
}

typedef ParameterInformation = {
    var label:String;
    @:optional var documentation:String;
}

typedef ReferenceParams = {
    >TextDocumentPositionParams,
    var context:ReferenceContext;
}

typedef ReferenceContext = {
    var includeDeclaration:Bool;
}

typedef DocumentHighlight = {
    var range:Range;
    @:optional var kind:DocumentHighlightKind;
}

@:enum abstract DocumentHighlightKind(Int) to Int {
    var Text = 1;
    var Read = 2;
    var Write = 3;
}

typedef DocumentSymbolParams = {
    var textDocument:TextDocumentIdentifier;
}

typedef SymbolInformation = {
    var name:String;
    var kind:SymbolKind;
    var location:Location;
    @:optional var containerName:String;
}

@:enum abstract SymbolKind(Int) to Int {
    var File = 1;
    var Module = 2;
    var Namespace = 3;
    var Package = 4;
    var Class = 5;
    var Method = 6;
    var Property = 7;
    var Field = 8;
    var Constructor = 9;
    var Enum = 10;
    var Interface = 11;
    var Function = 12;
    var Variable = 13;
    var Constant = 14;
    var String = 15;
    var Number = 16;
    var Boolean = 17;
    var Array = 18;
}

typedef WorkspaceSymbolParams = {
    var query:String;
}

typedef CodeActionParams = {
    var textDocument:TextDocumentIdentifier;
    var range:Range;
    var context:CodeActionContext;
}

typedef CodeActionContext = {
    var diagnostics:Array<Diagnostic>;
}

typedef CodeLensParams = {
    var textDocument:TextDocumentIdentifier;
}

typedef CodeLens = {
    var range:Range;
    @:optional var command:Command;
    @:optional var data:Dynamic;
}

typedef DocumentFormattingParams = {
    var textDocument:TextDocumentIdentifier;
    var options:FormattingOptions;
}

typedef FormattingOptions = {
    var tabSize:Int;
    var insertSpaces:Bool;
}

typedef DocumentOnTypeFormattingParams = {
    var textDocument:TextDocumentIdentifier;
    var position:Position;
    var ch:String;
    var options:FormattingOptions;
}

typedef RenameParams = {
    var textDocument:TextDocumentIdentifier;
    var position:Position;
    var newName:String;
}

import haxe.extern.EitherType;

import JsonRpc;
import Basic;

@:build(ProtocolMacro.build())
class Protocol {
    public function new() {}
    public function handleMessage(message:Message):Void {
        if (Reflect.hasField(message, "id"))
            handleRequest(cast message);
        else
            handleNotification(cast message);
    }

    public function handleRequest(request:RequestMessage):Void;
    public function handleNotification(notification:NotificationMessage):Void;
}

abstract Request<P,R,E>(String) to String {}
abstract Notification<P>(String) to String {}

@:enum abstract Method<P,R,E>(String) to String from Request<P,R,E> from Notification<P> {
    var Initialize : Method<InitializeParams,InitializeResult,InitializeError> = "initialize";
    var Shutdown : Notification<Void> = "shutdown";
    var Exit : Notification<Void> = "exit";

    var ShowMessage : Notification<ShowMessageParams> = "window/showMessage";
    var LogMessage : Notification<LogMessageParams> = "window/logMessage";

    var DidChangeConfiguration : Notification<DidChangeConfigurationParams> = "workspace/didChangeConfiguration";
    var DidOpenTextDocument : Notification<DidOpenTextDocumentParams> = "textDocument/didOpen";
    var DidChangeTextDocument : Notification<DidChangeTextDocumentParams> = "textDocument/didChange";
    var DidCloseTextDocument : Notification<DidCloseTextDocumentParams> = "textDocument/didClose";
    var DidSaveTextDocument : Notification<DidCloseTextDocumentParams> = "textDocument/didSave";
    var DidChangeWatchedFiles : Notification<DidChangeWatchedFilesParams> = "workspace/didChangeWatchedFiles";

    var PublishDiagnostics : Notification<PublishDiagnosticsParams> = "textDocument/publishDiagnostics";

    var Completion : Method<TextDocumentPositionParams,Array<CompletionItem>,Void> = "textDocument/completion";
    var CompletionItemResolve : Method<CompletionItem,CompletionItem,Void> = "completionItem/resolve";

    var Hover : Method<TextDocumentPositionParams,Hover,Void> = "textDocument/hover";
    var SignatureHelp : Method<TextDocumentPositionParams,SignatureHelp,Void> = "textDocument/signatureHelp";
    var GotoDefinition : Method<TextDocumentPositionParams,EitherType<Location,Array<Location>>,Void> = "textDocument/definition";
    var FindReferences : Method<ReferenceParams,Array<Location>,Void> = "textDocument/references";
    var DocumentHighlights : Method<TextDocumentPositionParams,DocumentHighlight,Void> = "textDocument/documentHighlight";
    var DocumentSymbols : Method<DocumentSymbolParams,Array<SymbolInformation>,Void> = "textDocument/documentSymbol";
    var WorkspaceSymbols : Method<WorkspaceSymbolParams,Array<SymbolInformation>,Void> = "workspace/symbol";
    var CodeAction : Method<CodeActionParams,Array<Command>,Void> = "textDocument/codeAction";

    var CodeLens : Method<CodeLensParams,Array<CodeLens>,Void> = "textDocument/codeLens";
    var CodeLensResolve : Method<CodeLens,CodeLens,Void> = "codeLens/resolve";

    var DocumentFormatting : Method<DocumentFormattingParams,Array<TextEdit>,Void> = "textDocument/formatting";
    var DocumentOnTypeFormatting : Method<DocumentOnTypeFormattingParams,Array<TextEdit>,Void> = "textDocument/onTypeFormatting";
    var Rename : Method<RenameParams,WorkspaceEdit,Void> = "textDocument/rename";    
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

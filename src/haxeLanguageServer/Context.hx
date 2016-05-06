package haxeLanguageServer;

import jsonrpc.Protocol;
import jsonrpc.Types;
import haxeLanguageServer.vscodeProtocol.ProtocolTypes;
import haxeLanguageServer.vscodeProtocol.Protocol;
import haxeLanguageServer.features.*;

class Context {
    public var workspacePath(default,null):String;
    public var displayArguments(get,never):Array<String>;
    public var protocol(default,null):Protocol;
    public var haxeServer(default,null):HaxeServer;
    public var documents(default,null):TextDocuments;
    var diagnostics:DiagnosticsFeature;

    var displayConfigurations:Array<Array<String>>;
    var displayConfigurationIndex:Int;

    inline function get_displayArguments() return displayConfigurations[displayConfigurationIndex];

    public function new(protocol) {
        this.protocol = protocol;
        protocol.onInitialize = onInitialize;
        protocol.onShutdown = onShutdown;
        protocol.onDidChangeConfiguration = onDidChangeConfiguration;
        protocol.onDidOpenTextDocument = onDidOpenTextDocument;
        protocol.onDidSaveTextDocument = onDidSaveTextDocument;
        protocol.onVSHaxeDidChangeDisplayConfigurationIndex = onDidChangeDisplayConfigurationIndex;
    }

    function onInitialize(params:InitializeParams, token:CancellationToken, resolve:InitializeResult->Void, reject:ResponseError<InitializeError>->Void) {
        workspacePath = params.rootPath;
        displayConfigurationIndex = (params.initializationOptions : InitOptions).displayConfigurationIndex;

        haxeServer = new HaxeServer(this);
        haxeServer.start(token, function(error) {
            if (error != null)
                return reject(new ResponseError(0, error, {retry: false}));

            documents = new TextDocuments(protocol);

            new CompletionFeature(this);
            new HoverFeature(this);
            new SignatureHelpFeature(this);
            new GotoDefinitionFeature(this);
            new FindReferencesFeature(this);
            new DocumentSymbolsFeature(this);

            diagnostics = new DiagnosticsFeature(this);

            return resolve({
                capabilities: {
                    textDocumentSync: TextDocuments.syncKind,
                    completionProvider: {
                        triggerCharacters: ["."]
                    },
                    signatureHelpProvider: {
                        triggerCharacters: ["(", ","]
                    },
                    definitionProvider: true,
                    hoverProvider: true,
                    referencesProvider: true,
                    documentSymbolProvider: true,
                    codeActionProvider: true
                }
            });
        });
    }

    function onDidChangeDisplayConfigurationIndex(params:{index:Int}) {
        displayConfigurationIndex = params.index;
    }

    function onShutdown(token:CancellationToken, resolve:Void->Void, _) {
        haxeServer.stop();
        haxeServer = null;
        return resolve();
    }

    function onDidChangeConfiguration(config:DidChangeConfigurationParams) {
        var config:Config = config.settings.haxe;
        displayConfigurations = config.displayConfigurations;
    }

    function onDidOpenTextDocument(event:DidOpenTextDocumentParams) {
        documents.onDidOpenTextDocument(event);
        diagnostics.getDiagnostics(event.textDocument.uri);
    }

    function onDidSaveTextDocument(event:DidSaveTextDocumentParams) {
        documents.onDidSaveTextDocument(event);
        diagnostics.getDiagnostics(event.textDocument.uri);
    }
}

private typedef Config = {
    var displayConfigurations:Array<Array<String>>;
}

private typedef InitOptions = {
    var displayConfigurationIndex:Int;
}

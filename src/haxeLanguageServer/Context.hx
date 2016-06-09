package haxeLanguageServer;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import vscodeProtocol.Protocol;
import vscodeProtocol.Types;
import haxeLanguageServer.features.*;

private typedef Config = {
    var displayConfigurations:Array<Array<String>>;
    var enableDiagnostics:Bool;
}

private typedef InitOptions = {
    var displayConfigurationIndex:Int;
}

class Context {
    public var workspacePath(default,null):String;
    public var displayArguments(get,never):Array<String>;
    public var protocol(default,null):Protocol;
    public var haxeServer(default,null):HaxeServer;
    public var documents(default,null):TextDocuments;
    var diagnostics:DiagnosticsFeature;

    var config:Config;
    var displayConfigurationIndex:Int;

    inline function get_displayArguments() return config.displayConfigurations[displayConfigurationIndex];

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

    function onDidChangeConfiguration(newConfig:DidChangeConfigurationParams) {
        this.config = newConfig.settings.haxe;
    }

    function onDidOpenTextDocument(event:DidOpenTextDocumentParams) {
        documents.onDidOpenTextDocument(event);
        if (config.enableDiagnostics)
            diagnostics.getDiagnostics(event.textDocument.uri);
    }

    function onDidSaveTextDocument(event:DidSaveTextDocumentParams) {
        documents.onDidSaveTextDocument(event);
        if (config.enableDiagnostics)
            diagnostics.getDiagnostics(event.textDocument.uri);
    }
}

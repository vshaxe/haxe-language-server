package haxeLanguageServer;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import vscodeProtocol.Protocol;
import vscodeProtocol.Types;
import haxeLanguageServer.features.*;

private typedef Config = {
    var displayConfigurations:Array<Array<String>>;
    var enableDiagnostics:Bool;
    var displayServerArguments:Array<String>;
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

    @:allow(haxeLanguageServer.HaxeServer)
    var config:Config;
    var displayConfigurationIndex:Int;

    inline function get_displayArguments() return config.displayConfigurations[displayConfigurationIndex];

    public function new(protocol) {
        this.protocol = protocol;

        haxeServer = new HaxeServer(this);

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
        documents = new TextDocuments(protocol);
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
        var firstInit = (config == null);

        config = newConfig.settings.haxe;

        if (firstInit) {
            haxeServer.start(function() {
                new CompletionFeature(this);
                new HoverFeature(this);
                new SignatureHelpFeature(this);
                new GotoDefinitionFeature(this);
                new FindReferencesFeature(this);
                new DocumentSymbolsFeature(this);

                diagnostics = new DiagnosticsFeature(this);
                if (config.enableDiagnostics) {
                    for (doc in documents.getAll())
                        diagnostics.getDiagnostics(doc.uri);
                }
            });
        } else {
            haxeServer.restart("configuration was changed");
        }
    }

    function onDidOpenTextDocument(event:DidOpenTextDocumentParams) {
        documents.onDidOpenTextDocument(event);
        if (diagnostics != null && config.enableDiagnostics)
            diagnostics.getDiagnostics(event.textDocument.uri);
    }

    function onDidSaveTextDocument(event:DidSaveTextDocumentParams) {
        documents.onDidSaveTextDocument(event);
        if (diagnostics != null && config.enableDiagnostics)
            diagnostics.getDiagnostics(event.textDocument.uri);
    }
}

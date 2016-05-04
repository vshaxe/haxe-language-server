import jsonrpc.Protocol;
import jsonrpc.Types;
import vscodeProtocol.ProtocolTypes;

class Context {
    public var workspacePath(default,null):String;
    public var displayArguments(default,null):Array<String>;
    public var protocol(default,null):vscodeProtocol.Protocol;
    public var haxeServer(default,null):HaxeServer;
    public var documents(default,null):TextDocuments;
    var diagnostics:features.DiagnosticsFeature;

    public function new(protocol) {
        this.protocol = protocol;
        protocol.onInitialize = onInitialize;
        protocol.onShutdown = onShutdown;
        protocol.onDidChangeConfiguration = onDidChangeConfiguration;
        protocol.onDidOpenTextDocument = onDidOpenTextDocument;
        protocol.onDidSaveTextDocument = onDidSaveTextDocument;
    }

    function onInitialize(params:InitializeParams, token:CancellationToken, resolve:InitializeResult->Void, reject:ResponseError<InitializeError>->Void) {
        workspacePath = params.rootPath;

        haxeServer = new HaxeServer(this);
        haxeServer.start(token, function(error) {
            if (error != null)
                return reject(new ResponseError(0, error, {retry: false}));

            documents = new TextDocuments(protocol);

            new features.CompletionFeature(this);
            new features.HoverFeature(this);
            new features.SignatureHelpFeature(this);
            new features.GotoDefinitionFeature(this);
            new features.FindReferencesFeature(this);
            new features.DocumentSymbolsFeature(this);

            diagnostics = new features.DiagnosticsFeature(this);

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

    function onShutdown(token:CancellationToken, resolve:Void->Void, _) {
        haxeServer.stop();
        haxeServer = null;
        return resolve();
    }

    function onDidChangeConfiguration(config:DidChangeConfigurationParams) {
        var config:Config = config.settings.haxe;
        displayArguments = config.displayArguments;
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
    var displayArguments:Array<String>;
}

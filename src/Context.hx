import jsonrpc.Protocol;
import vscode.ProtocolTypes;

class Context {
    public var workspacePath(default,null):String;
    public var hxmlFile(default,null):String;
    public var protocol(default,null):vscode.Protocol;
    public var haxeServer(default,null):HaxeServer;
    var documents:TextDocuments;

    static inline var HAXE_SERVER_PORT = 6000;

    public function new(protocol) {
        this.protocol = protocol;
        protocol.onInitialize = onInitialize;
        protocol.onShutdown = onShutdown;
        protocol.onDidChangeConfiguration = onDidChangeConfiguration;
    }

    function onInitialize(params:InitializeParams, cancelToken:CancelToken, resolve:InitializeResult->Void, reject:RejectDataHandler<InitializeError>) {
        workspacePath = params.rootPath;

        haxeServer = new HaxeServer();
        haxeServer.start(HAXE_SERVER_PORT);

        documents = new TextDocuments();
        documents.listen(protocol);

        new features.CompletionFeature(this);
        new features.HoverFeature(this);
        new features.SignatureHelpFeature(this);
        new features.GotoDefinitionFeature(this);
        new features.FindReferencesFeature(this);
        new features.DocumentSymbolsFeature(this);

        return resolve({
            capabilities: {
                textDocumentSync: TextDocuments.syncKind,
                completionProvider: {
                    triggerCharacters: ["."]
                },
                signatureHelpProvider: {
                    triggerCharacters: ["("]
                },
                definitionProvider: true,
                hoverProvider: true,
                referencesProvider: true,
                documentSymbolProvider: true,
            }
        });
    }

    function onShutdown(cancelToken:CancelToken, resolve:Void->Void, reject:RejectHandler) {
        haxeServer.stop();
        haxeServer = null;
        return resolve();
    }

    function onDidChangeConfiguration(config:DidChangeConfigurationParams) {
        var config:Config = config.settings.haxe;
        hxmlFile = config.buildFile;
    }

    public inline function getDocument(uri:String):TextDocument {
        return documents.get(uri);
    }
}

private typedef Config = {
    var buildFile:String;
}

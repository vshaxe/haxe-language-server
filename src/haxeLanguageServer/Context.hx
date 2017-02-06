package haxeLanguageServer;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types;
import jsonrpc.Protocol;
import haxeLanguageServer.features.*;
import haxeLanguageServer.helper.TypeHelper.FunctionFormattingConfig;

private typedef DisplayServerConfigBase = {
    var haxePath:String;
    var arguments:Array<String>;
    var env:haxe.DynamicAccess<String>;
}

private typedef DisplayServerConfig = {
    >DisplayServerConfigBase,
    @:optional var windows:DisplayServerConfigBase;
    @:optional var linux:DisplayServerConfigBase;
    @:optional var osx:DisplayServerConfigBase;
}

private typedef FunctionGenerationConfig = {
    @:optional var anonymous:FunctionFormattingConfig;
}

private typedef CodeGenerationConfig = {
    @:optional var functions:FunctionGenerationConfig;
}

private typedef Config = {
    var displayConfigurations:Array<Array<String>>;
    var enableDiagnostics:Bool;
    var diagnosticsPathFilter:String;
    var enableCodeLens:Bool;
    var displayServer:DisplayServerConfig;
    var displayPort:Null<Int>;
    var buildCompletionCache:Bool;
    var codeGeneration:CodeGenerationConfig;
}

private typedef InitOptions = {
    var displayConfigurationIndex:Int;
}

class Context {
    static var systemKey = switch (Sys.systemName()) {
        case "Windows": "windows";
        case "Mac": "osx";
        default: "linux";
    };

    public var workspacePath(default,null):String;
    public var displayArguments(get,never):Array<String>;
    public var protocol(default,null):Protocol;
    public var haxeServer(default,null):HaxeServer;
    public var documents(default,null):TextDocuments;
    public var codeActions(default,null):CodeActionFeature;
    public var signatureHelp(default,null):SignatureHelpFeature;
    var diagnostics:DiagnosticsManager;

    public var config(default, null):Config;
    @:allow(haxeLanguageServer.HaxeServer)
    var displayServerConfig:DisplayServerConfigBase;
    var displayConfigurationIndex:Int;

    inline function get_displayArguments() return config.displayConfigurations[displayConfigurationIndex];

    public function new(protocol) {
        this.protocol = protocol;

        haxeServer = new HaxeServer(this);

        protocol.onRequest(Methods.Initialize, onInitialize);
        protocol.onRequest(Methods.Shutdown, onShutdown);
        protocol.onNotification(Methods.DidChangeConfiguration, onDidChangeConfiguration);
        protocol.onNotification(Methods.DidOpenTextDocument, onDidOpenTextDocument);
        protocol.onNotification(Methods.DidSaveTextDocument, onDidSaveTextDocument);
        protocol.onNotification(VshaxeMethods.DidChangeDisplayConfigurationIndex, onDidChangeDisplayConfigurationIndex);
    }

    public inline function sendShowMessage(type:MessageType, message:String) {
        protocol.sendNotification(Methods.ShowMessage, {type: type, message: message});
    }

    public inline function sendLogMessage(type:MessageType, message:String) {
        protocol.sendNotification(Methods.LogMessage, {type: type, message: message});
    }

    function onInitialize(params:InitializeParams, token:CancellationToken, resolve:InitializeResult->Void, reject:ResponseError<InitializeError>->Void) {
        workspacePath = params.rootPath;
        displayConfigurationIndex = (params.initializationOptions : InitOptions).displayConfigurationIndex;
        documents = new TextDocuments(protocol);
        return resolve({
            capabilities: {
                textDocumentSync: TextDocuments.syncKind,
                completionProvider: {
                    triggerCharacters: [".", "@", ":"]
                },
                signatureHelpProvider: {
                    triggerCharacters: ["(", ","]
                },
                definitionProvider: true,
                hoverProvider: true,
                referencesProvider: true,
                documentSymbolProvider: true,
                workspaceSymbolProvider: true,
                codeActionProvider: true,
                codeLensProvider: {
                    resolveProvider: true
                }
            }
        });
    }

    function onDidChangeDisplayConfigurationIndex(params:{index:Int}) {
        displayConfigurationIndex = params.index;
        haxeServer.restart("selected configuration was changed");
    }

    function onShutdown(_, token:CancellationToken, resolve:NoData->Void, _) {
        haxeServer.stop();
        haxeServer = null;
        return resolve(null);
    }

    function onDidChangeConfiguration(newConfig:DidChangeConfigurationParams) {
        var firstInit = (config == null);

        config = newConfig.settings.haxe;
        updateDisplayServerConfig();
        updateCodeGenerationConfig();

        if (firstInit) {
            haxeServer.start(function() {
                codeActions = new CodeActionFeature(this);

                new CompletionFeature(this);
                new HoverFeature(this);
                signatureHelp = new SignatureHelpFeature(this);
                new GotoDefinitionFeature(this);
                new FindReferencesFeature(this);
                new DocumentSymbolsFeature(this);
                new DeterminePackageFeature(this);

                diagnostics = new DiagnosticsManager(this);
                new CodeLensFeature(this);
                new CodeGenerationFeature(this);

                if (config.enableDiagnostics) {
                    for (doc in documents.getAll())
                        diagnostics.publishDiagnostics(doc.uri);
                }
            });
        } else {
            haxeServer.restart("configuration was changed");
        }
    }

    function updateDisplayServerConfig() {
        displayServerConfig = {
            haxePath: "haxe",
            arguments: [],
            env: {},
        };

        function merge(conf:DisplayServerConfigBase) {
            if (conf.haxePath != null)
                displayServerConfig.haxePath = conf.haxePath;
            if (conf.arguments != null)
                displayServerConfig.arguments = conf.arguments;
            if (conf.env != null)
                displayServerConfig.env = conf.env;
        }

        var conf = config.displayServer;
        if (conf != null) {
            merge(conf);
            var sysConf:DisplayServerConfigBase = Reflect.field(conf, systemKey);
            if (sysConf != null)
                merge(sysConf);
        }
    }

    function updateCodeGenerationConfig() {
        var codeGen = config.codeGeneration;
        if (codeGen.functions == null)
            codeGen.functions = {};

        var functions = codeGen.functions;
        if (functions.anonymous == null)
            functions.anonymous = {argumentTypeHints: false, returnTypeHint: Never};
    }

    function onDidOpenTextDocument(event:DidOpenTextDocumentParams) {
        documents.onDidOpenTextDocument(event);
        if (diagnostics != null && config.enableDiagnostics)
            diagnostics.publishDiagnostics(event.textDocument.uri);
    }

    function onDidSaveTextDocument(event:DidSaveTextDocumentParams) {
        if (diagnostics != null && config.enableDiagnostics)
            diagnostics.publishDiagnostics(event.textDocument.uri);
    }

    public function callDisplay(args:Array<String>, stdin:String, token:CancellationToken, callback:String->Void, errback:String->Void) {
        if (displayArguments == null)
            return;

        var actualArgs = ["--cwd", workspacePath]; // change cwd to workspace root
        actualArgs = actualArgs.concat(displayArguments); // add arguments from the workspace settings
        actualArgs = actualArgs.concat([
            "-D", "display-details", // get more details in completion results,
            "--no-output", // prevent anygeneration
        ]);
        actualArgs = actualArgs.concat(args); // finally, add given query args
        haxeServer.process(actualArgs, token, stdin, callback, errback);
    }
}

package haxeLanguageServer;

import haxe.Timer;
import haxe.Json;
import haxe.extern.EitherType;
import js.Node.process;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types;
import jsonrpc.Protocol;
import haxeLanguageServer.features.*;
import haxeLanguageServer.features.CodeActionFeature.CodeActionContributor;
import haxeLanguageServer.helper.SemVer;
import haxeLanguageServer.helper.TypeHelper.FunctionFormattingConfig;
import haxeLanguageServer.helper.ImportHelper;
import haxeLanguageServer.server.DisplayResult;
import haxeLanguageServer.server.HaxeServer;

private typedef FunctionGenerationConfig = {
    @:optional var anonymous:FunctionFormattingConfig;
}

private typedef ImportGenerationConfig = {
    var enableAutoImports:Bool;
    var style:ImportStyle;
}

private typedef CodeGenerationConfig = {
    @:optional var functions:FunctionGenerationConfig;
    @:optional var imports:ImportGenerationConfig;
}

private typedef Config = {
    var enableDiagnostics:Bool;
    var diagnosticsPathFilter:String;
    var enableCodeLens:Bool;
    var displayPort:Null<EitherType<Int, String>>;
    var buildCompletionCache:Bool;
    var codeGeneration:CodeGenerationConfig;
    var format:haxeFormatter.Config;
}

private typedef InitOptions = {
    var displayServerConfig:DisplayServerConfig;
    var displayArguments:Array<String>;
}

class Context {
    public var workspacePath(default,null):FsPath;
    public var capabilities(default,null):ClientCapabilities;
    public var displayArguments(default,null):Array<String>;
    public var protocol(default,null):Protocol;
    public var haxeServer(default,null):HaxeServer;
    public var documents(default,null):TextDocuments;
    public var signatureHelp(default,null):SignatureHelpFeature;
    public var displayOffsetConverter(default,null):DisplayOffsetConverter;
    public var gotoDefinition(default,null):GotoDefinitionFeature;
    var diagnostics:DiagnosticsManager;
    var codeActions:CodeActionFeature;
    var activeEditor:DocumentUri;

    public var config(default,null):Config;
    var unmodifiedConfig:Config;
    final defaultConfig:Config;
    @:allow(haxeLanguageServer.server.HaxeServer)
    var displayServerConfig:DisplayServerConfig;

    var progressId = 0;

    public function new(protocol) {
        this.protocol = protocol;
        haxeServer = new HaxeServer(this);
        defaultConfig = {
            enableDiagnostics: true,
            diagnosticsPathFilter: "${workspaceRoot}",
            enableCodeLens: false,
            displayPort: null,
            buildCompletionCache: true,
            codeGeneration: {},
            format: {}
        };

        protocol.onRequest(Methods.Initialize, onInitialize);
        protocol.onRequest(Methods.Shutdown, onShutdown);
        protocol.onNotification(Methods.Exit, onExit);
        protocol.onNotification(Methods.DidChangeConfiguration, onDidChangeConfiguration);
        protocol.onNotification(Methods.DidOpenTextDocument, onDidOpenTextDocument);
        protocol.onNotification(Methods.DidSaveTextDocument, onDidSaveTextDocument);
        protocol.onNotification(Methods.DidChangeWatchedFiles, onDidChangeWatchedFiles);
        protocol.onNotification(HaxeMethods.DidChangeDisplayArguments, onDidChangeDisplayArguments);
        protocol.onNotification(HaxeMethods.DidChangeDisplayServerConfig, onDidChangeDisplayServerConfig);
        protocol.onNotification(HaxeMethods.DidChangeActiveTextEditor, onDidChangeActiveTextEditor);
    }

    inline function isInitialized():Bool {
        return config != null;
    }

    public function startProgress(title:String):Void->Void {
        var id = progressId++;
        protocol.sendNotification(HaxeMethods.ProgressStart, {id: id, title: 'Haxe: $title...'});
        return function() {
            protocol.sendNotification(HaxeMethods.ProgressStop, {id: id});
        };
    }

    public inline function sendShowMessage(type:MessageType, message:String) {
        protocol.sendNotification(Methods.ShowMessage, {type: type, message: message});
    }

    public inline function sendLogMessage(type:MessageType, message:String) {
        protocol.sendNotification(Methods.LogMessage, {type: type, message: message});
    }

    function onInitialize(params:InitializeParams, token:CancellationToken, resolve:InitializeResult->Void, reject:ResponseError<InitializeError>->Void) {
        workspacePath = params.rootUri.toFsPath();
        capabilities = params.capabilities;
        var options = (params.initializationOptions : InitOptions);
        if (options == null) {
            displayServerConfig = {
                path: "haxe",
                env: new haxe.DynamicAccess(),
                arguments: []
            };
            displayArguments = [];
        } else {
            displayServerConfig = options.displayServerConfig;
            displayArguments = options.displayArguments;
        }
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
                #if debug
                documentFormattingProvider: true,
                #end
                codeLensProvider: {
                    resolveProvider: true
                },
                renameProvider: true
            }
        });
    }

    function onDidChangeDisplayArguments(params:{arguments:Array<String>}) {
        displayArguments = params.arguments;
        restartServer("display arguments changed");
    }

    function onDidChangeDisplayServerConfig(config:DisplayServerConfig) {
        displayServerConfig = config;
        restartServer("display server configuration changed");
    }

    function onShutdown(_, token:CancellationToken, resolve:NoData->Void, _) {
        haxeServer.stop();
        haxeServer = null;
        return resolve(null);
    }

    function onExit(_) {
        if (haxeServer != null) {
            haxeServer.stop();
            haxeServer = null;
            process.exit(1);
        } else {
            process.exit(0);
        }
    }

    function onDidChangeConfiguration(newConfig:DidChangeConfigurationParams) {
        var initialized = isInitialized();
        var newHaxeConfig = newConfig.settings.haxe;
        if (newHaxeConfig == null) {
            newHaxeConfig = {};
        }

        var newConfigJson = Json.stringify(newHaxeConfig);
        var configUnchanged = Json.stringify(unmodifiedConfig) == newConfigJson;
        if (initialized && configUnchanged) {
            return;
        }
        unmodifiedConfig = Json.parse(newConfigJson);

        processSettings(newHaxeConfig);
        updateCodeGenerationConfig();

        if (!initialized) {
            haxeServer.start(function() {
                onServerStarted();

                codeActions = new CodeActionFeature(this);
                new CompletionFeature(this);
                new HoverFeature(this);
                signatureHelp = new SignatureHelpFeature(this);
                gotoDefinition = new GotoDefinitionFeature(this);
                new FindReferencesFeature(this);
                new DocumentSymbolsFeature(this);
                new DeterminePackageFeature(this);
                new RenameFeature(this);
                diagnostics = new DiagnosticsManager(this);
                new CodeLensFeature(this);
                new CodeGenerationFeature(this);

                #if debug
                new DocumentFormattingFeature(this);
                #end

                for (doc in documents.getAll())
                    publishDiagnostics(doc.uri);
            });
        } else {
            restartServer("configuration was changed");
        }
    }

    function processSettings(newConfig:Dynamic) {
        // this is a hacky way to completely ignore uninteresting config sections
        // to do this properly, we need to make language server not watch the whole haxe.* section,
        // but only what's interesting for us
        Reflect.deleteField(newConfig, "displayServer");
        Reflect.deleteField(newConfig, "displayConfigurations");
        Reflect.deleteField(newConfig, "executable");

        config = newConfig;

        // apply defaults
        if (config.enableDiagnostics == null)
            config.enableDiagnostics = defaultConfig.enableDiagnostics;
        if (config.diagnosticsPathFilter == null)
            config.diagnosticsPathFilter = defaultConfig.diagnosticsPathFilter;
        if (config.enableCodeLens == null)
            config.enableCodeLens = defaultConfig.enableCodeLens;
        if (config.buildCompletionCache == null)
            config.buildCompletionCache = defaultConfig.buildCompletionCache;
        if (config.codeGeneration == null)
            config.codeGeneration = defaultConfig.codeGeneration;
        if (config.format == null)
            config.format = defaultConfig.format;
    }

    function updateCodeGenerationConfig() {
        var codeGen = config.codeGeneration;
        if (codeGen.functions == null)
            codeGen.functions = {};

        var functions = codeGen.functions;
        if (functions.anonymous == null)
            functions.anonymous = {argumentTypeHints: false, returnTypeHint: Never, useArrowSyntax: true, prefixPackages: true};

        if (codeGen.imports == null)
            codeGen.imports = {enableAutoImports: true, style: Type};

        var imports = codeGen.imports;
        if (imports.enableAutoImports == null)
            imports.enableAutoImports = true;
        if (imports.style == null)
            imports.style = Type;
    }

    function onServerStarted() {
        displayOffsetConverter = DisplayOffsetConverter.create(haxeServer.version);

        var hasArrowFunctions = haxeServer.version >= new SemVer(4, 0, 0);
        if (!hasArrowFunctions)
            config.codeGeneration.functions.anonymous.useArrowSyntax = false;
    }

    function restartServer(reason:String) {
        if (!isInitialized()) {
            return;
        }
        haxeServer.restart(reason, function() {
            onServerStarted();
            if (activeEditor != null) {
                publishDiagnostics(activeEditor);
            }
        });
    }

    function onDidOpenTextDocument(event:DidOpenTextDocumentParams) {
        activeEditor = event.textDocument.uri;
        documents.onDidOpenTextDocument(event);
        publishDiagnostics(event.textDocument.uri);
    }

    function onDidSaveTextDocument(event:DidSaveTextDocumentParams) {
        publishDiagnostics(event.textDocument.uri);
    }

    function onDidChangeWatchedFiles(event:DidChangeWatchedFilesParams) {
        for (change in event.changes) {
            if (change.type == Deleted) {
                diagnostics.clearDiagnostics(change.uri);
            }
        }
    }

    function onDidChangeActiveTextEditor(params:{uri:DocumentUri}) {
        activeEditor = params.uri;
        var document = documents.get(params.uri);
        if (document == null)
            return;
        // avoid running diagnostics twice when the document is initially opened (open + activate event)
        var timeSinceOpened = Timer.stamp() - document.openTimestamp;
        if (timeSinceOpened > 0.1)
            publishDiagnostics(params.uri);
    }

    function publishDiagnostics(uri:DocumentUri) {
        if (diagnostics != null && config.enableDiagnostics)
            diagnostics.publishDiagnostics(uri);
    }

    public function callDisplay(args:Array<String>, stdin:String, token:CancellationToken, callback:DisplayResult->Void, errback:String->Void) {
        var actualArgs = ["--cwd", workspacePath.toString()]; // change cwd to workspace root
        if (displayArguments != null)
            actualArgs = actualArgs.concat(displayArguments); // add arguments from the workspace settings
        actualArgs = actualArgs.concat([
            "-D", "display-details", // get more details in completion results,
            "--no-output", // prevent anygeneration
        ]);
        actualArgs = actualArgs.concat(args); // finally, add given query args
        haxeServer.process(actualArgs, token, true, stdin, Processed(callback, errback));
    }

    public function registerCodeActionContributor(contributor:CodeActionContributor) {
        codeActions.registerContributor(contributor);
    }
}

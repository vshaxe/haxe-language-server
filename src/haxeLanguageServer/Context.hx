package haxeLanguageServer;

import haxe.CallStack;
import haxe.Json;
import haxe.extern.EitherType;
import js.Node.process;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types;
import jsonrpc.Protocol;
import haxeLanguageServer.features.*;
import haxeLanguageServer.features.completion.*;
import haxeLanguageServer.features.CodeActionFeature.CodeActionContributor;
import haxeLanguageServer.helper.SemVer;
import haxeLanguageServer.helper.FunctionFormattingConfig;
import haxeLanguageServer.helper.ImportHelper;
import haxeLanguageServer.helper.StructDefaultsMacro;
import haxeLanguageServer.server.DisplayResult;
import haxeLanguageServer.server.HaxeServer;
import haxeLanguageServer.protocol.Protocol.HaxeRequestMethod;
import haxeLanguageServer.protocol.Protocol.Response;
import haxeLanguageServer.protocol.Protocol.Methods as HaxeMethods;
import haxeLanguageServer.protocol.Server.ServerMethods;
import haxeLanguageServer.protocol.Display.DisplayMethods;
import haxeLanguageServer.LanguageServerMethods.HaxeMethodResult;
import languageServerProtocol.protocol.TypeDefinition.TypeDefinitionMethods;

private typedef FunctionGenerationConfig = {
    var ?anonymous:FunctionFormattingConfig;
    var ?field:FunctionFormattingConfig;
}

private typedef ImportGenerationConfig = {
    var ?enableAutoImports:Bool;
    var ?style:ImportStyle;
}

private typedef CodeGenerationConfig = {
    var ?functions:FunctionGenerationConfig;
    var ?imports:ImportGenerationConfig;
}

private typedef Config = {
    var ?enableCodeLens:Bool;
    var ?enableDiagnostics:Bool;
    var ?enableMethodsView:Bool;
    var ?enableSignatureHelpDocumentation:Bool;
    var ?diagnosticsPathFilter:String;
    var ?displayPort:Null<EitherType<Int, String>>;
    var ?buildCompletionCache:Bool;
    var ?codeGeneration:CodeGenerationConfig;
    var ?exclude:Array<String>;
}

private typedef InitOptions = {
    var ?displayServerConfig:DisplayServerConfig;
    var ?displayArguments:Array<String>;
    var ?sendMethodResults:Bool;
}

class Context {
    public final protocol:Protocol;
    public var haxeServer(default,null):HaxeServer;
    public var workspacePath(default,null):FsPath;
    public var capabilities(default,null):ClientCapabilities;
    public var displayArguments(default,null):Array<String>;
    public var documents(default,null):TextDocuments;
    public var signatureHelp(default,null):SignatureHelpFeature;
    public var displayOffsetConverter(default,null):DisplayOffsetConverter;
    public var gotoDefinition(default,null):GotoDefinitionFeature;
    public var sendMethodResults(default,null):Bool = false;
    var diagnostics:DiagnosticsManager;
    var codeActions:CodeActionFeature;
    var activeEditor:DocumentUri;

    public var config(default,null):Config;
    var unmodifiedConfig:Config;
    final defaultConfig:Config;
    @:allow(haxeLanguageServer.server.HaxeServer)
    var displayServerConfig:DisplayServerConfig;

    var progressId = 0;
    var nextRequestId:Int = 0;

    public function new(protocol) {
        this.protocol = protocol;
        haxeServer = new HaxeServer(this);
        defaultConfig = {
            enableCodeLens: false,
            enableDiagnostics: true,
            enableMethodsView: false,
            enableSignatureHelpDocumentation: true,
            diagnosticsPathFilter: "${workspaceRoot}",
            displayPort: null,
            buildCompletionCache: true,
            codeGeneration: {
                functions: {
                    anonymous: {
                        returnTypeHint: Never,
                        argumentTypeHints: false,
                        useArrowSyntax: true,
                        explicitNull: false,
                    },
                    field: {
                        returnTypeHint: NonVoid,
                        argumentTypeHints: true,
                        placeOpenBraceOnNewLine: false,
                        explicitPublic: false,
                        explicitPrivate: false,
                        explicitNull: false,
                    }
                },
                imports: {
                    style: Type,
                    enableAutoImports: true
                }
            },
            exclude: [
                "zpp_nape"
            ]
        };

        protocol.onRequest(Methods.Initialize, onInitialize);
        protocol.onRequest(Methods.Shutdown, onShutdown);
        protocol.onNotification(Methods.Exit, onExit);
        protocol.onNotification(Methods.DidChangeConfiguration, onDidChangeConfiguration);
        protocol.onNotification(Methods.DidOpenTextDocument, onDidOpenTextDocument);
        protocol.onNotification(Methods.DidChangeTextDocument, onDidChangeTextDocument);
        protocol.onNotification(Methods.DidCloseTextDocument, onDidCloseTextDocument);
        protocol.onNotification(Methods.DidSaveTextDocument, onDidSaveTextDocument);
        protocol.onNotification(Methods.DidChangeWatchedFiles, onDidChangeWatchedFiles);
        protocol.onNotification(LanguageServerMethods.DidChangeDisplayArguments, onDidChangeDisplayArguments);
        protocol.onNotification(LanguageServerMethods.DidChangeDisplayServerConfig, onDidChangeDisplayServerConfig);
        protocol.onNotification(LanguageServerMethods.DidChangeActiveTextEditor, onDidChangeActiveTextEditor);
        protocol.onNotification(LanguageServerMethods.RunMethod, runMethod);
    }

    inline function isInitialized():Bool {
        return config != null;
    }

    public function startProgress(title:String):Void->Void {
        var id = progressId++;
        protocol.sendNotification(LanguageServerMethods.ProgressStart, {id: id, title: 'Haxe: $title...'});
        return function() {
            protocol.sendNotification(LanguageServerMethods.ProgressStop, {id: id});
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

        var options:InitOptions = params.initializationOptions;
        var defaults:InitOptions = {
            displayServerConfig: {
                path: "haxe",
                env: new haxe.DynamicAccess(),
                arguments: [],
                print: {
                    completion: false,
                    reusing: false
                }
            },
            displayArguments: [],
            sendMethodResults: false
        };
        StructDefaultsMacro.applyDefaults(options, defaults);
        displayServerConfig = options.displayServerConfig;
        displayArguments = options.displayArguments;
        sendMethodResults = options.sendMethodResults;

        documents = new TextDocuments(protocol);
        new DocumentSymbolsFeature(this);
        #if debug
        new DocumentFormattingFeature(this);
        #end

        return resolve({
            capabilities: {
                textDocumentSync: TextDocuments.syncKind,
                completionProvider: {
                    triggerCharacters: [".", "@", ":", " ", ">"],
                    resolveProvider: true
                },
                signatureHelpProvider: {
                    triggerCharacters: ["(", ","]
                },
                definitionProvider: true,
                hoverProvider: true,
                referencesProvider: true,
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

        if (!initialized) {
            haxeServer.start(function() {
                onServerStarted();

                codeActions = new CodeActionFeature(this);
                new CompletionFeature(this);
                new HoverFeature(this);
                signatureHelp = new SignatureHelpFeature(this);
                gotoDefinition = new GotoDefinitionFeature(this);
                new GotoTypeDefinitionFeature(this);
                new FindReferencesFeature(this);
                new DeterminePackageFeature(this);
                new RenameFeature(this);
                diagnostics = new DiagnosticsManager(this);
                new CodeLensFeature(this);
                new CodeGenerationFeature(this);
                new WorkspaceSymbolsFeature(this);

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

        StructDefaultsMacro.applyDefaults(config, defaultConfig);
    }

    function onServerStarted() {
        displayOffsetConverter = DisplayOffsetConverter.create(haxeServer.version);

        var hasArrowFunctions = haxeServer.version >= new SemVer(4, 0, 0);
        if (!hasArrowFunctions)
            config.codeGeneration.functions.anonymous.useArrowSyntax = false;

        if (haxeServer.supports(DisplayMethods.GotoTypeDefinition)) {
            protocol.sendRequest(Methods.RegisterCapability, {
                registrations: [{
                    id: TypeDefinitionMethods.TypeDefinition,
                    method: TypeDefinitionMethods.TypeDefinition
                }]
            }, null, _ -> {}, error -> trace(error));
        } else {
            protocol.sendRequest(Methods.UnregisterCapability, {
                unregisterations: [{
                    id: TypeDefinitionMethods.TypeDefinition,
                    method: TypeDefinitionMethods.TypeDefinition
                }]
            }, null, _ -> {}, error -> trace(error));
        }
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

    function onDidChangeTextDocument(event:DidChangeTextDocumentParams) {
        if (haxeServer.supports(ServerMethods.Invalidate)) {
            callHaxeMethod(ServerMethods.Invalidate, {file: event.textDocument.uri.toFsPath()}, null, _ -> null, error -> {
                trace("Error during " + ServerMethods.Invalidate + " " + error);
            });
        }
        documents.onDidChangeTextDocument(event);
    }

    function onDidCloseTextDocument(event:DidCloseTextDocumentParams) {
        documents.onDidCloseTextDocument(event);
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
        var timeSinceOpened = haxe.Timer.stamp() - document.openTimestamp;
        if (timeSinceOpened > 0.1)
            publishDiagnostics(params.uri);
    }

    function publishDiagnostics(uri:DocumentUri) {
        if (diagnostics != null && config.enableDiagnostics)
            diagnostics.publishDiagnostics(uri);
    }

    function runMethod(params:{method:String, params:Any}) {
        callHaxeMethod(cast params.method, params.params, null, _ -> null, _ -> {});
    }

    public function callHaxeMethod<P,R>(method:HaxeRequestMethod<P,Response<R>>, ?params:P, token:CancellationToken, callback:R->String, errback:(error:String)->Void) {
        // TODO: avoid duplicating jsonrpc.Protocol logic
        var id = nextRequestId++;
        var request:RequestMessage = {
            jsonrpc: @:privateAccess jsonrpc.Protocol.PROTOCOL_VERSION,
            id: id,
            method: method
        };
        if (params != null)
            request.params = params;
        var requestJson = Json.stringify(request);

        callDisplay(method, [requestJson], null, token, result -> {
            var arrivalTime = Date.now().getTime();
            switch (result) {
                case DResult(data):
                    var response:ResponseMessage = try {
                        Json.parse(data);
                    } catch (e:Any) {
                        return errback(Std.string(e));
                    }
                    if (Reflect.hasField(response, "error"))
                        errback(response.error.message);
                    else
                        runHaxeMethodCallback(response, arrivalTime, callback, errback, method);
                case DCancelled:
            }
        }, error -> {
            // this should never happen (if on a Haxe version that supports JSON-RPC)
            errback(error);
        });
    }

    function runHaxeMethodCallback(response, arrivalTime, callback, errback:String->Void, method) {
        var haxeResponse:Response<Dynamic> = response.result;
        if (!sendMethodResults) {
            callback(haxeResponse.result);
            return;
        }

        var beforeProcessingTime = Date.now().getTime();
        var debugInfo =
            try
                callback(haxeResponse.result)
            catch (e:Any) {
                errback(e);
                trace(e);
                trace(CallStack.toString(CallStack.exceptionStack()));
                null;
            }
        var afterProcessingTime = Date.now().getTime();
        var methodResult:HaxeMethodResult = {
            method: method,
            debugInfo: debugInfo,
            additionalTimes: {
                arrival: arrivalTime,
                beforeProcessing: beforeProcessingTime,
                afterProcessing: afterProcessingTime
            },
            response: haxeResponse
        };
        protocol.sendNotification(LanguageServerMethods.DidRunHaxeMethod, methodResult);
    }

    public function callDisplay(label:String, args:Array<String>, stdin:String, token:CancellationToken, callback:DisplayResult->Void, errback:(error:String)->Void) {
        var actualArgs = ["--cwd", workspacePath.toString()]; // change cwd to workspace root
        if (displayArguments != null)
            actualArgs = actualArgs.concat(displayArguments); // add arguments from the workspace settings
        actualArgs = actualArgs.concat([
            "-D", "display-details", // get more details in completion results,
            "--no-output", // prevent any generation
        ]);
        if (haxeServer.supports(HaxeMethods.Initialize) && config.enableMethodsView) {
            actualArgs = actualArgs.concat([
                "--times",
                "-D", "macro-times"
            ]);
        }
        actualArgs.push("--display");
        actualArgs = actualArgs.concat(args); // finally, add given query args
        haxeServer.process(label, actualArgs, token, true, stdin, Processed(callback, errback));
    }

    public function registerCodeActionContributor(contributor:CodeActionContributor) {
        codeActions.registerContributor(contributor);
    }

    public function startTimer(method:String) {
        var startTime = Date.now().getTime();
        return function(result:Dynamic, ?debugInfo:String) {
            if (sendMethodResults) {
                protocol.sendNotification(LanguageServerMethods.DidRunHaxeMethod, {
                    method: method,
                    debugInfo: debugInfo,
                    response: {
                        timestamp: 0,
                        timers: {
                            name: method,
                            time: (Date.now().getTime() - startTime) / 1000,
                        },
                        result: result
                    }
                });
            }
        };
    }
}

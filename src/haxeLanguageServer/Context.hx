package haxeLanguageServer;

import haxe.CallStack;
import haxe.Json;
import js.Node.process;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types;
import jsonrpc.Protocol;
import haxeLanguageServer.features.*;
import haxeLanguageServer.features.completion.*;
import haxeLanguageServer.features.documentSymbols.DocumentSymbolsFeature;
import haxeLanguageServer.features.foldingRange.FoldingRangeFeature;
import haxeLanguageServer.features.CodeActionFeature.CodeActionContributor;
import haxeLanguageServer.server.DisplayResult;
import haxeLanguageServer.server.HaxeServer;
import haxeLanguageServer.protocol.Protocol.HaxeRequestMethod;
import haxeLanguageServer.protocol.Protocol.Response;
import haxeLanguageServer.protocol.Protocol.Methods as HaxeMethods;
import haxeLanguageServer.protocol.Protocol.HaxeResponseErrorData;
import haxeLanguageServer.protocol.Server.ServerMethods;
import haxeLanguageServer.protocol.Display.DisplayMethods;
import haxeLanguageServer.LanguageServerMethods.HaxeMethodResult;
import languageServerProtocol.protocol.TypeDefinition.TypeDefinitionMethods;

class Context {
	public final config:Configuration;
	public final languageServerProtocol:Protocol;
	public final haxeDisplayProtocol:Protocol;
	public var haxeServer(default, null):HaxeServer;
	public var workspacePath(default, null):FsPath;
	public var capabilities(default, null):ClientCapabilities;
	public var documents(default, null):TextDocuments;
	public var displayOffsetConverter(default, null):DisplayOffsetConverter;
	public var gotoDefinition(default, null):GotoDefinitionFeature;
	public var determinePackage(default, null):DeterminePackageFeature;

	var diagnostics:DiagnosticsFeature;
	var codeActions:CodeActionFeature;
	var activeEditor:DocumentUri;
	var initialized = false;
	var progressId = 0;

	public function new(languageServerProtocol) {
		config = new Configuration(languageServerProtocol, kind -> restartServer('$kind configuration was changed'));
		this.languageServerProtocol = languageServerProtocol;

		haxeDisplayProtocol = new Protocol((message, token) -> {
			var method:String = Reflect.field(message, "method");
			if (method == Protocol.CANCEL_METHOD) {
				return; // don't send cancel notifications, not supported by Haxe
			}
			var includeDisplayArguments = method.startsWith("display/") || method == ServerMethods.ReadClassPaths;
			callDisplay(method, [Json.stringify(message)], token, function(result:DisplayResult) {
				switch result {
					case DResult(msg):
						haxeDisplayProtocol.handleMessage(Json.parse(msg));
					case DCancelled:
				}
			}, function(error) {
				haxeDisplayProtocol.handleMessage(try {
					Json.parse(error);
				} catch (_:Any) {
					// pretend we got a proper JSON (HaxeFoundation/haxe#7955)
					var message:ResponseMessage = {
						jsonrpc: Protocol.PROTOCOL_VERSION,
						id: @:privateAccess haxeDisplayProtocol.nextRequestId - 1, // ew..
						error: new ResponseError(ResponseError.InternalError, "Compiler error", ([
							{
								severity: Error,
								message: error
							}
						] : HaxeResponseErrorData))
					}
					message;
				});
			}, includeDisplayArguments);
		});

		haxeServer = new HaxeServer(this);

		languageServerProtocol.onRequest(Methods.Initialize, onInitialize);
		languageServerProtocol.onRequest(Methods.Shutdown, onShutdown);
		languageServerProtocol.onNotification(Methods.Exit, onExit);
		languageServerProtocol.onNotification(Methods.DidOpenTextDocument, onDidOpenTextDocument);
		languageServerProtocol.onNotification(Methods.DidChangeTextDocument, onDidChangeTextDocument);
		languageServerProtocol.onNotification(Methods.DidCloseTextDocument, onDidCloseTextDocument);
		languageServerProtocol.onNotification(Methods.DidSaveTextDocument, onDidSaveTextDocument);
		languageServerProtocol.onNotification(Methods.DidChangeWatchedFiles, onDidChangeWatchedFiles);

		languageServerProtocol.onNotification(LanguageServerMethods.DidChangeActiveTextEditor, onDidChangeActiveTextEditor);
		languageServerProtocol.onRequest(LanguageServerMethods.RunMethod, runMethod);
	}

	public function startProgress(title:String):Void->Void {
		var id = progressId++;
		languageServerProtocol.sendNotification(LanguageServerMethods.ProgressStart, {id: id, title: 'Haxe: $title...'});
		return function() {
			languageServerProtocol.sendNotification(LanguageServerMethods.ProgressStop, {id: id});
		};
	}

	public inline function sendShowMessage(type:MessageType, message:String) {
		languageServerProtocol.sendNotification(Methods.ShowMessage, {type: type, message: message});
	}

	public inline function sendLogMessage(type:MessageType, message:String) {
		languageServerProtocol.sendNotification(Methods.LogMessage, {type: type, message: message});
	}

	function onInitialize(params:InitializeParams, _, resolve:InitializeResult->Void, _) {
		if (params.rootUri != null) {
			workspacePath = params.rootUri.toFsPath();
		}
		capabilities = params.capabilities;
		config.onInitialize(params);

		documents = new TextDocuments(this);
		new DocumentSymbolsFeature(this);
		new FoldingRangeFeature(this);
		new DocumentFormattingFeature(this);

		return resolve({
			capabilities: {
				textDocumentSync: {
					openClose: true,
					change: TextDocuments.syncKind,
					save: {
						includeText: false
					}
				},
				completionProvider: {
					triggerCharacters: [".", "@", ":", " ", ">", "$"],
					resolveProvider: true
				},
				signatureHelpProvider: {
					triggerCharacters: ["(", ","]
				},
				definitionProvider: true,
				hoverProvider: true,
				referencesProvider: true,
				documentSymbolProvider: true,
				workspaceSymbolProvider: true,
				codeActionProvider: {
					codeActionKinds: [QuickFix, SourceOrganizeImports]
				},
				documentFormattingProvider: true,
				renameProvider: true,
				foldingRangeProvider: true
			}
		});
	}

	function onShutdown(_, _, resolve:NoData->Void, _) {
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

	function onServerStarted() {
		displayOffsetConverter = DisplayOffsetConverter.create(haxeServer.version);

		if (haxeServer.supports(DisplayMethods.GotoTypeDefinition)) {
			registerCapability({
				id: TypeDefinitionMethods.TypeDefinition,
				method: TypeDefinitionMethods.TypeDefinition
			});
		} else {
			unregisterCapability({
				id: TypeDefinitionMethods.TypeDefinition,
				method: TypeDefinitionMethods.TypeDefinition
			});
		}
	}

	public function registerCapability(registration:Registration) {
		languageServerProtocol.sendRequest(Methods.RegisterCapability, {
			registrations: [registration]
		}, null, _ -> {}, error -> trace(error));
	}

	public function unregisterCapability(unregistration:Unregistration) {
		languageServerProtocol.sendRequest(Methods.UnregisterCapability, {
			unregisterations: [unregistration]
		}, null, _ -> {}, error -> trace(error));
	}

	function restartServer(reason:String) {
		if (!initialized) {
			haxeServer.start(function() {
				onServerStarted();

				codeActions = new CodeActionFeature(this);
				new CompletionFeature(this);
				new HoverFeature(this);
				new SignatureHelpFeature(this);
				gotoDefinition = new GotoDefinitionFeature(this);
				new GotoTypeDefinitionFeature(this);
				new FindReferencesFeature(this);
				determinePackage = new DeterminePackageFeature(this);
				new RenameFeature(this);
				diagnostics = new DiagnosticsFeature(this);
				new CodeLensFeature(this);
				new CodeGenerationFeature(this);
				new WorkspaceSymbolsFeature(this);

				for (doc in documents.getAll())
					publishDiagnostics(doc.uri);

				initialized = true;
			});
		} else {
			haxeServer.restart(reason, function() {
				onServerStarted();
				if (activeEditor != null) {
					publishDiagnostics(activeEditor);
				}
			});
		}
	}

	function isUriSupported(uri:DocumentUri):Bool {
		return uri.isFile() || uri.isUntitled();
	}

	function onDidOpenTextDocument(event:DidOpenTextDocumentParams) {
		var uri = event.textDocument.uri;
		if (isUriSupported(uri)) {
			activeEditor = uri;
			documents.onDidOpenTextDocument(event);
			publishDiagnostics(uri);
		}
	}

	function onDidChangeTextDocument(event:DidChangeTextDocumentParams) {
		var uri = event.textDocument.uri;
		if (isUriSupported(uri)) {
			if (uri.isFile() && haxeServer.supports(ServerMethods.Invalidate)) {
				callHaxeMethod(ServerMethods.Invalidate, {file: uri.toFsPath()}, null, _ -> null, error -> {
					trace("Error during " + ServerMethods.Invalidate + " " + error);
				});
			}
			documents.onDidChangeTextDocument(event);
		}
	}

	function onDidCloseTextDocument(event:DidCloseTextDocumentParams) {
		if (isUriSupported(event.textDocument.uri)) {
			documents.onDidCloseTextDocument(event);
		}
	}

	function onDidSaveTextDocument(event:DidSaveTextDocumentParams) {
		var uri = event.textDocument.uri;
		if (isUriSupported(uri)) {
			publishDiagnostics(uri);
		}
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
		if (diagnostics != null && config.user.enableDiagnostics)
			diagnostics.publishDiagnostics(uri);
	}

	function runMethod(params:{method:String, params:Any}, token:CancellationToken, resolve:Dynamic->Void, reject:ResponseError<NoData>->Void) {
		callHaxeMethod(cast params.method, params.params, token, function(response) {
			resolve(response);
			return null;
		}, function(error) {
			reject(new ResponseError(0, error));
		});
	}

	public function callHaxeMethod<P, R>(method:HaxeRequestMethod<P, Response<R>>, ?params:P, ?token:CancellationToken, callback:(result:R) -> Null<String>,
			errback:(error:String) -> Void) {
		var beforeCallTime = Date.now().getTime();
		haxeDisplayProtocol.sendRequest(method, params, token, function(response) {
			var arrivalTime = Date.now().getTime();
			if (!config.sendMethodResults) {
				callback(response.result);
				return;
			}

			var beforeProcessingTime = Date.now().getTime();
			var debugInfo:Null<String> = try callback(response.result) catch (e:Any) {
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
					beforeCall: beforeCallTime,
					arrival: arrivalTime,
					beforeProcessing: beforeProcessingTime,
					afterProcessing: afterProcessingTime
				},
				response: response
			};
			languageServerProtocol.sendNotification(LanguageServerMethods.DidRunHaxeMethod, methodResult);
		}, function(error:ResponseErrorData) {
			var data:HaxeResponseErrorData = error.data;
			errback(data[0].message);
		});
	}

	public function callDisplay(label:String, args:Array<String>, ?stdin:String, ?token:CancellationToken, callback:DisplayResult->Void,
			errback:(error:String) -> Void, includeDisplayArguments:Bool = true) {
		var actualArgs = [];
		if (includeDisplayArguments) {
			actualArgs = actualArgs.concat(["--cwd", workspacePath.toString()]);
			if (config.displayArguments != null)
				actualArgs = actualArgs.concat(config.displayArguments); // add arguments from the workspace settings
			actualArgs = actualArgs.concat([
				"-D",
				"display-details", // get more details in completion results,
				"--no-output", // prevent any generation
			]);
		}
		if (haxeServer.supports(HaxeMethods.Initialize) && config.user.enableServerView) {
			actualArgs = actualArgs.concat(["--times", "-D", "macro-times"]);
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
		return function(?result:Dynamic, ?debugInfo:String) {
			if (config.sendMethodResults) {
				languageServerProtocol.sendNotification(LanguageServerMethods.DidRunHaxeMethod, {
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

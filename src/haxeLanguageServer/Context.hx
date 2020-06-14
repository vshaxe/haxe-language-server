package haxeLanguageServer;

import haxe.Json;
import haxe.display.Display.DisplayMethods;
import haxe.display.Protocol.HaxeRequestMethod;
import haxe.display.Protocol.HaxeResponseErrorData;
import haxe.display.Protocol.Methods as HaxeMethods;
import haxe.display.Protocol.Response;
import haxe.display.Server.ServerMethods;
import haxeLanguageServer.LanguageServerMethods.MethodResult;
import haxeLanguageServer.features.haxe.*;
import haxeLanguageServer.features.haxe.codeAction.*;
import haxeLanguageServer.features.haxe.codeAction.CodeActionFeature.CodeActionContributor;
import haxeLanguageServer.features.haxe.completion.*;
import haxeLanguageServer.features.haxe.documentSymbols.DocumentSymbolsFeature;
import haxeLanguageServer.features.haxe.foldingRange.FoldingRangeFeature;
import haxeLanguageServer.server.DisplayResult;
import haxeLanguageServer.server.HaxeServer;
import js.Node.process;
import jsonrpc.CancellationToken;
import jsonrpc.Protocol;
import jsonrpc.ResponseError;
import jsonrpc.Types;
import languageServerProtocol.protocol.Implementation;
import languageServerProtocol.protocol.Progress;
import languageServerProtocol.protocol.TypeDefinition.TypeDefinitionRequest;

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
			if (method == CancelNotification.type) {
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

		languageServerProtocol.onRequest(InitializeRequest.type, onInitialize);
		languageServerProtocol.onRequest(ShutdownRequest.type, onShutdown);
		languageServerProtocol.onNotification(ExitNotification.type, onExit);
		languageServerProtocol.onNotification(DidOpenTextDocumentNotification.type, onDidOpenTextDocument);
		languageServerProtocol.onNotification(DidChangeTextDocumentNotification.type, onDidChangeTextDocument);
		languageServerProtocol.onNotification(DidCloseTextDocumentNotification.type, onDidCloseTextDocument);
		languageServerProtocol.onNotification(DidSaveTextDocumentNotification.type, onDidSaveTextDocument);
		languageServerProtocol.onNotification(DidChangeWatchedFilesNotification.type, onDidChangeWatchedFiles);

		languageServerProtocol.onNotification(LanguageServerMethods.DidChangeActiveTextEditor, onDidChangeActiveTextEditor);
		languageServerProtocol.onRequest(LanguageServerMethods.RunMethod, runMethod);
	}

	public function startProgress(title:String):() -> Void {
		if (capabilities.window!.workDoneProgress == false) {
			return function() {};
		}
		var id = progressId++;
		languageServerProtocol.sendRequest(WorkDoneProgressCreateRequest.type, {token: id});
		languageServerProtocol.sendProgress(WorkDoneProgress.type, id, {kind: Begin, title: 'Haxe: $title...'});
		return function() {
			languageServerProtocol.sendProgress(WorkDoneProgress.type, id, ({kind: End} : WorkDoneProgressEnd));
		};
	}

	public inline function sendShowMessage(type:MessageType, message:String) {
		languageServerProtocol.sendNotification(ShowMessageNotification.type, {type: type, message: message});
	}

	public inline function sendLogMessage(type:MessageType, message:String) {
		languageServerProtocol.sendNotification(LogMessageNotification.type, {type: type, message: message});
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
				documentFormattingProvider: true,
				documentRangeFormattingProvider: true,
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
		displayOffsetConverter = DisplayOffsetConverter.create(haxeServer.haxeVersion);

		function handleRegistration<P, R>(displayMethod:HaxeRequestMethod<P, R>, lspMethod:String) {
			if (haxeServer.supports(displayMethod)) {
				registerCapability(lspMethod);
			} else {
				unregisterCapability(lspMethod);
			}
		}
		handleRegistration(DisplayMethods.GotoTypeDefinition, TypeDefinitionRequest.type);
		handleRegistration(DisplayMethods.GotoImplementation, ImplementationRequest.type);
	}

	public function registerCapability(method:String, ?registerOptions:Dynamic) {
		var params:Registration = {
			id: method,
			method: method
		};
		if (registerOptions != null) {
			params.registerOptions = registerOptions;
		}
		languageServerProtocol.sendRequest(RegistrationRequest.type, {
			registrations: [params]
		}, null, _ -> {}, error -> trace(error));
	}

	public function unregisterCapability(method:String) {
		languageServerProtocol.sendRequest(UnregistrationRequest.type, {
			unregisterations: [
				{
					id: method,
					method: method
				}
			]
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
				new GotoImplementationFeature(this);
				new GotoTypeDefinitionFeature(this);
				new FindReferencesFeature(this);
				determinePackage = new DeterminePackageFeature(this);
				new RenameFeature(this);
				diagnostics = new DiagnosticsFeature(this);
				new CodeLensFeature(this);
				new CodeGenerationFeature(this);
				new WorkspaceSymbolsFeature(this);
				new ExtractTypeFeature(this);
				new ExtractConstantFeature(this);
				new ExtractFunctionFeature(this);

				for (doc in documents)
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
			callFileParamsMethod(uri, ServerMethods.Invalidate);
			documents.onDidChangeTextDocument(event);
		}
	}

	function onDidCloseTextDocument(event:DidCloseTextDocumentParams) {
		var uri = event.textDocument.uri;
		if (isUriSupported(uri)) {
			documents.onDidCloseTextDocument(event);
			diagnostics.clearDiagnostics(uri);
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
			switch change.type {
				case Created:
					callFileParamsMethod(change.uri, ServerMethods.ModuleCreated);
				case Deleted:
					diagnostics.clearDiagnostics(change.uri);
					callFileParamsMethod(change.uri, ServerMethods.Invalidate);
				case _:
			}
		}
	}

	function callFileParamsMethod(uri:DocumentUri, method) {
		if (uri.isFile() && haxeServer.supports(method)) {
			callHaxeMethod(method, {file: uri.toFsPath()}, null, _ -> null, error -> {
				trace("Error during " + method + " " + error);
			});
		}
	}

	function onDidChangeActiveTextEditor(params:{uri:DocumentUri}) {
		activeEditor = params.uri;
		var document = documents.getHaxe(params.uri);
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
		haxeDisplayProtocol.sendRequest(cast method, params, token, function(response) {
			var arrivalTime = Date.now().getTime();
			if (!config.sendMethodResults) {
				callback(response.result);
				return;
			}

			var beforeProcessingTime = Date.now().getTime();
			var debugInfo:Null<String> = try {
				callback(response.result);
			} catch (e) {
				errback(e.toString());
				trace(e);
				trace(e.stack);
				null;
			}
			var afterProcessingTime = Date.now().getTime();
			var methodResult:MethodResult = {
				kind: Haxe,
				method: method,
				debugInfo: debugInfo,
				additionalTimes: {
					beforeCall: beforeCallTime,
					arrival: arrivalTime,
					beforeProcessing: beforeProcessingTime,
					afterProcessing: afterProcessingTime
				},
				response: cast response
			};
			languageServerProtocol.sendNotification(LanguageServerMethods.DidRunMethod, methodResult);
		}, function(error:ResponseErrorData) {
			var data:HaxeResponseErrorData = error.data;
			errback(data[0].message);
		});
	}

	public function callDisplay(label:String, args:Array<String>, ?stdin:String, ?token:CancellationToken, callback:DisplayResult->Void,
			errback:(error:String) -> Void, includeDisplayArguments:Bool = true) {
		var actualArgs = [];
		if (includeDisplayArguments) {
			actualArgs = actualArgs.concat([
				"--cwd",
				workspacePath.toString(),
				"-D",
				"display-details", // get more details in completion results,
				"--no-output", // prevent any generation
			]);
		}
		if (haxeServer.supports(HaxeMethods.Initialize) && config.user.enableServerView) {
			actualArgs = actualArgs.concat(["--times", "-D", "macro-times"]);
		}

		// this must be the final argument before --display to avoid issues with --next
		// see haxe issue #8795
		if (includeDisplayArguments && config.displayArguments != null)
			actualArgs = actualArgs.concat(config.displayArguments); // add arguments from the workspace settings

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
				languageServerProtocol.sendNotification(LanguageServerMethods.DidRunMethod, {
					kind: Haxe,
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

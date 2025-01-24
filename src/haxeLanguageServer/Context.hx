package haxeLanguageServer;

import haxe.Json;
import haxe.display.Display.DisplayMethods;
import haxe.display.Protocol.HaxeRequestMethod;
import haxe.display.Protocol.HaxeResponseErrorData;
import haxe.display.Protocol.Methods as HaxeMethods;
import haxe.display.Protocol.Response;
import haxe.display.Server.ServerMethods;
import haxeLanguageServer.Configuration.ExperimentalCapabilities;
import haxeLanguageServer.Configuration.InitOptions;
import haxeLanguageServer.LanguageServerMethods.MethodResult;
import haxeLanguageServer.features.CompletionFeature;
import haxeLanguageServer.features.HoverFeature;
import haxeLanguageServer.features.haxe.CodeLensFeature;
import haxeLanguageServer.features.haxe.ColorProviderFeature;
import haxeLanguageServer.features.haxe.DeterminePackageFeature;
import haxeLanguageServer.features.haxe.DiagnosticsFeature;
import haxeLanguageServer.features.haxe.DocumentFormattingFeature;
import haxeLanguageServer.features.haxe.FindReferencesFeature;
import haxeLanguageServer.features.haxe.GotoDefinitionFeature;
import haxeLanguageServer.features.haxe.GotoImplementationFeature;
import haxeLanguageServer.features.haxe.GotoTypeDefinitionFeature;
import haxeLanguageServer.features.haxe.InlayHintFeature;
import haxeLanguageServer.features.haxe.InlineValueFeature;
import haxeLanguageServer.features.haxe.RefactorFeature;
import haxeLanguageServer.features.haxe.RenameFeature;
import haxeLanguageServer.features.haxe.SignatureHelpFeature;
import haxeLanguageServer.features.haxe.WorkspaceSymbolsFeature;
import haxeLanguageServer.features.haxe.codeAction.CodeActionFeature;
import haxeLanguageServer.features.haxe.documentSymbols.DocumentSymbolsFeature;
import haxeLanguageServer.features.haxe.foldingRange.FoldingRangeFeature;
import haxeLanguageServer.features.haxe.refactoring.RefactorCache;
import haxeLanguageServer.server.DisplayResult;
import haxeLanguageServer.server.HaxeServer;
import haxeLanguageServer.server.ServerRecording;
import js.Node.process;
import jsonrpc.CancellationToken;
import jsonrpc.Protocol;
import jsonrpc.ResponseError;
import jsonrpc.Types;
import languageServerProtocol.protocol.ColorProvider.DocumentColorRequest;
import languageServerProtocol.protocol.FoldingRange.FoldingRangeRequest;
import languageServerProtocol.protocol.Implementation;
import languageServerProtocol.protocol.InlayHints;
import languageServerProtocol.protocol.InlineValue.InlineValueRequest;
import languageServerProtocol.protocol.Messages.ProtocolRequestType;
import languageServerProtocol.protocol.Progress;
import languageServerProtocol.protocol.TypeDefinition.TypeDefinitionRequest;

class Context {
	public static final haxeSelector:DocumentSelector = [{language: "haxe", scheme: "file"}, {language: "haxe", scheme: "untitled"}];
	public static final hxmlSelector:DocumentSelector = [{language: "hxml", scheme: "file"}, {language: "hxml", scheme: "untitled"}];

	public final config:Configuration;
	public final languageServerProtocol:Protocol;
	public final haxeDisplayProtocol:Protocol;

	public var documents(default, null):TextDocuments;
	public var latestActiveFilePackage = "";

	public var serverRecording(default, null):ServerRecording;
	@:nullSafety(Off) public var haxeServer:HaxeServer;
	@:nullSafety(Off) public var workspacePath(default, null):FsPath;
	@:nullSafety(Off) public var capabilities(default, null):ClientCapabilities;
	@:nullSafety(Off) public var displayOffsetConverter(default, null):DisplayOffsetConverter;
	@:nullSafety(Off) public var gotoDefinition(default, null):GotoDefinitionFeature;
	@:nullSafety(Off) public var findReferences(default, null):FindReferencesFeature;
	@:nullSafety(Off) public var determinePackage(default, null):DeterminePackageFeature;
	@:nullSafety(Off) public var diagnostics(default, null):DiagnosticsFeature;
	@:nullSafety(Off) public var refactorCache(default, null):RefactorCache;
	public var experimental(default, null):Null<ExperimentalCapabilities>;

	var activeEditor:Null<DocumentUri>;
	var initialized = false;
	var progressId = 0;

	var invalidated = new Map<String, Bool>();

	public function new(languageServerProtocol) {
		this.languageServerProtocol = languageServerProtocol;
		serverRecording = new ServerRecording();
		haxeDisplayProtocol = new Protocol(@:nullSafety(Off) writeMessage);
		haxeServer = @:nullSafety(Off) new HaxeServer(this);
		documents = new TextDocuments();
		config = new Configuration(languageServerProtocol, kind -> restartServer('$kind configuration was changed'));

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
		languageServerProtocol.onRequest(LanguageServerMethods.ExportServerRecording, serverRecording.export);
	}

	function writeMessage(message:Message, token:Null<CancellationToken>) {
		final method:String = Reflect.field(message, "method");
		if (method == CancelNotification.type) {
			return; // don't send cancel notifications, not supported by Haxe
		}
		final includeDisplayArguments = method.startsWith("display/") || method == ServerMethods.ReadClassPaths;
		callDisplay(method, [Json.stringify(message)], token, function(result:DisplayResult) {
			switch result {
				case DResult("") if (method == DisplayMethods.Diagnostics):
					haxeDisplayProtocol.handleMessage(({
						jsonrpc: Protocol.PROTOCOL_VERSION,
						id: (cast message : RequestMessage).id,
						result: {result: []}
					} : ResponseMessage));
				case DResult(msg):
					haxeDisplayProtocol.handleMessage(Json.parse(msg));
				case DCancelled:
			}
		}, function(error) {
			haxeDisplayProtocol.handleMessage(try {
				Json.parse(error);
			} catch (_:Any) {
				// pretend we got a proper JSON (HaxeFoundation/haxe#7955)
				final message:ResponseMessage = {
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
	}

	public function startProgress(title:String):() -> Void {
		if (capabilities.window?.workDoneProgress == false) {
			return function() {};
		}
		final id = progressId++;
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

	public function resetInvalidatedFiles():Void {
		invalidated = [];
	}

	function onInitialize(params:InitializeParams, _, resolve:InitializeResult->Void, _) {
		if (params.rootUri != null) {
			workspacePath = params.rootUri.toFsPath();
		}
		capabilities = params.capabilities;
		final initOptions:Null<InitOptions> = params.initializationOptions;
		experimental = initOptions?.experimentalClientCapabilities ?? {};
		config.onInitialize(params);
		serverRecording.onInitialize(this);

		new DocumentSymbolsFeature(this);
		new FoldingRangeFeature(this);
		new DocumentFormattingFeature(this);
		new ColorProviderFeature(this);
		new InlayHintFeature(this);

		final textDocument = capabilities?.textDocument;
		final workspace = capabilities?.workspace;
		final registrations = new Array<Registration>();
		function register<P, R, PR, E, RO>(method:ProtocolRequestType<P, R, PR, E, RO>, ?registerId:String, ?selector:DocumentSelector, ?registerOptions:RO) {
			if (registerOptions == null) {
				registerOptions = cast {documentSelector: selector};
			}

			final id = registerId ?? '$method';
			registrations.push({id: id, method: method, registerOptions: registerOptions});
		}

		final capabilities:ServerCapabilities = {
			textDocumentSync: {
				openClose: true,
				change: TextDocuments.syncKind,
				save: {
					includeText: false
				}
			}
		};

		final completionTriggerCharacters = [".", "@", ":", " ", ">", "$"];
		if (textDocument?.completion?.dynamicRegistration == true) {
			register(CompletionRequest.type, "haxeDocument/completion", {
				documentSelector: haxeSelector,
				triggerCharacters: completionTriggerCharacters,
				resolveProvider: true
			});
			register(CompletionRequest.type, "hxmlDocument/completion", {
				documentSelector: hxmlSelector,
				triggerCharacters: ["-", "/", "\\", "=", " "],
				resolveProvider: true
			});
		} else {
			capabilities.completionProvider = {
				triggerCharacters: completionTriggerCharacters,
				resolveProvider: true
			}
		}

		final signatureHelpTriggerCharacters = ["(", ","];
		if (textDocument?.signatureHelp?.dynamicRegistration == true) {
			register(SignatureHelpRequest.type, {
				documentSelector: haxeSelector,
				triggerCharacters: signatureHelpTriggerCharacters
			});
		} else {
			capabilities.signatureHelpProvider = {
				triggerCharacters: signatureHelpTriggerCharacters
			}
		}

		if (textDocument?.definition?.dynamicRegistration == true) {
			register(DefinitionRequest.type, haxeSelector);
		} else {
			capabilities.definitionProvider = true;
		}

		if (textDocument?.hover?.dynamicRegistration == true) {
			register(HoverRequest.type, "haxeDocument/hover", haxeSelector);
			register(HoverRequest.type, "hxmlDocument/hover", hxmlSelector);
		} else {
			capabilities.hoverProvider = true;
		}

		if (textDocument?.references?.dynamicRegistration == true) {
			register(ReferencesRequest.type, haxeSelector);
		} else {
			capabilities.referencesProvider = true;
		}

		if (textDocument?.documentSymbol?.dynamicRegistration == true) {
			register(DocumentSymbolRequest.type, haxeSelector);
		} else {
			capabilities.documentSymbolProvider = true;
		}

		if (workspace?.symbol?.dynamicRegistration == true) {
			register(WorkspaceSymbolRequest.type, haxeSelector);
		} else {
			capabilities.workspaceSymbolProvider = true;
		}

		if (textDocument?.formatting?.dynamicRegistration == true) {
			register(DocumentFormattingRequest.type, haxeSelector);
		} else {
			capabilities.documentFormattingProvider = true;
		}

		if (textDocument?.rangeFormatting?.dynamicRegistration == true) {
			register(DocumentRangeFormattingRequest.type, haxeSelector);
		} else {
			capabilities.documentRangeFormattingProvider = true;
		}

		if (textDocument?.rename?.dynamicRegistration == true) {
			register(RenameRequest.type, {documentSelector: haxeSelector, prepareProvider: true});
		} else {
			if (textDocument?.rename?.prepareSupport == true) {
				capabilities.renameProvider = {
					prepareProvider: true
				};
			} else {
				capabilities.renameProvider = true;
			}
		}

		if (textDocument?.foldingRange?.dynamicRegistration == true) {
			register(FoldingRangeRequest.type, haxeSelector);
		} else {
			capabilities.foldingRangeProvider = true;
		}

		if (textDocument?.colorProvider?.dynamicRegistration == true) {
			// this registration covers both documentColor and colorPresentation
			register(DocumentColorRequest.type, haxeSelector);
		} else {
			capabilities.colorProvider = true;
		}

		if (textDocument?.inlayHint?.dynamicRegistration == true) {
			register(InlayHintRequest.type, haxeSelector);
		} else {
			capabilities.inlayHintProvider = true;
		}

		if (textDocument?.inlineValue?.dynamicRegistration == true) {
			register(InlineValueRequest.type, haxeSelector);
		} else {
			capabilities.inlineValueProvider = true;
		}

		resolve({capabilities: capabilities});
		languageServerProtocol.sendRequest(RegistrationRequest.type, {registrations: registrations}, null, _ -> {}, error -> trace(error));
	}

	@:nullSafety(Off)
	function onShutdown(_, _, resolve:NoData->Void, _) {
		haxeServer.stop();
		return resolve(null);
	}

	function onExit(_) {
		if (haxeServer != null) {
			haxeServer.stop();
			process.exit(1);
		} else {
			process.exit(0);
		}
	}

	function onServerStarted() {
		displayOffsetConverter = DisplayOffsetConverter.create(haxeServer.haxeVersion);
		handleRegistration(DisplayMethods.GotoTypeDefinition, TypeDefinitionRequest.type, {documentSelector: haxeSelector});
		handleRegistration(DisplayMethods.GotoImplementation, ImplementationRequest.type, {documentSelector: haxeSelector});
	}

	function handleRegistration<HP, HR, P, R, PR, E, RO>(displayMethod:HaxeRequestMethod<HP, HR>, lspMethod:ProtocolRequestType<P, R, PR, E, RO>,
			registerOptions:RO) {
		if (haxeServer.supports(displayMethod)) {
			registerCapability(lspMethod, registerOptions);
		} else {
			unregisterCapability(lspMethod);
		}
	}

	public function registerCapability<P, R, PR, E, RO>(method:ProtocolRequestType<P, R, PR, E, RO>, ?registerId:String, registerOptions:RO) {
		languageServerProtocol.sendRequest(RegistrationRequest.type, {
			registrations: [
				{
					id: registerId ?? '$method',
					method: method,
					registerOptions: registerOptions
				}
			]
		}, null, _ -> {}, error -> trace(error));
	}

	public function unregisterCapability(method:String, ?registerId:String) {
		languageServerProtocol.sendRequest(UnregistrationRequest.type, {
			unregisterations: [
				{
					id: registerId ?? '$method',
					method: method
				}
			]
		}, null, _ -> {}, error -> trace(error));
	}

	public function hasClientCommandSupport(command:String):Bool {
		final supportedCommands = experimental?.supportedCommands ?? return false;
		return supportedCommands.contains(command);
	}

	function restartServer(reason:String) {
		serverRecording.restartServer(reason, this);

		if (!initialized) {
			haxeServer.start(function() {
				onServerStarted();

				new CompletionFeature(this);
				new HoverFeature(this);
				new SignatureHelpFeature(this);
				gotoDefinition = new GotoDefinitionFeature(this);
				new GotoImplementationFeature(this);
				new GotoTypeDefinitionFeature(this);
				findReferences = new FindReferencesFeature(this);
				determinePackage = new DeterminePackageFeature(this);
				refactorCache = new RefactorCache(this);
				new RenameFeature(this, refactorCache);
				diagnostics = new DiagnosticsFeature(this);
				new CodeActionFeature(this);
				new CodeLensFeature(this);
				new WorkspaceSymbolsFeature(this);
				new InlineValueFeature(this, refactorCache);

				for (doc in documents) {
					publishDiagnostics(doc.uri);
				}
				initialized = true;
			});
		} else {
			haxeServer.restart(reason, function() {
				onServerStarted();
				refactorCache.initClassPaths();
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
		final uri = event.textDocument.uri;
		if (isUriSupported(uri)) {
			activeEditor = uri;
			documents.onDidOpenTextDocument(event);
			publishDiagnostics(uri);
		}
	}

	function onDidChangeTextDocument(event:DidChangeTextDocumentParams) {
		final uri = event.textDocument.uri;
		if (isUriSupported(uri)) {
			serverRecording.onDidChangeTextDocument(event);
			invalidateFile(uri);
			documents.onDidChangeTextDocument(event);
			refactorCache.invalidateFile(uri.toFsPath().toString());
		}
	}

	function onDidCloseTextDocument(event:DidCloseTextDocumentParams) {
		final uri = event.textDocument.uri;
		if (isUriSupported(uri)) {
			documents.onDidCloseTextDocument(event);
			diagnostics.clearDiagnostics(uri);
		}
	}

	function onDidSaveTextDocument(event:DidSaveTextDocumentParams) {
		final uri = event.textDocument.uri;
		if (isUriSupported(uri)) {
			publishDiagnostics(uri);
			invalidated.remove(uri.toString());
			refactorCache.invalidateFile(uri.toFsPath().toString());
		}
	}

	function onDidChangeWatchedFiles(event:DidChangeWatchedFilesParams) {
		for (change in event.changes) {
			serverRecording.onFileEvent(change);

			switch change.type {
				case Created:
					callFileParamsMethod(change.uri, ServerMethods.ModuleCreated);
				case Deleted:
					diagnostics.clearDiagnostics(change.uri);
					invalidateFile(change.uri);
				case _:
			}
			if (change.uri.isHaxeFile()) {
				refactorCache.invalidateFile(change.uri.toFsPath().toString());
			}
		}
	}

	function invalidateFile(uri:DocumentUri) {
		if (!invalidated.exists(uri.toString())) {
			callFileParamsMethod(uri, ServerMethods.Invalidate);
			invalidated.set(uri.toString(), true);
		}
	}

	function callFileParamsMethod(uri:DocumentUri, method) {
		if (uri.isFile() && uri.isHaxeFile() && haxeServer.supports(method)) {
			callHaxeMethod(method, {file: uri.toFsPath()}, null, _ -> null, error -> {
				trace("Error during " + method + " " + error);
			});
		}
	}

	function onDidChangeActiveTextEditor(params:{uri:DocumentUri}) {
		if (!params.uri.isFile() || !params.uri.isHaxeFile()) {
			return;
		}
		activeEditor = params.uri;
		final document = documents.getHaxe(params.uri);
		if (document == null) {
			return;
		}
		// avoid running diagnostics twice when the document is initially opened (open + activate event)
		final timeSinceOpened = haxe.Timer.stamp() - document.openTimestamp;
		if (timeSinceOpened > 0.1) {
			publishDiagnostics(params.uri);
			invalidated.remove(activeEditor.toString());
		}
		updateActiveEditorPackage(activeEditor);
	}

	function updateActiveEditorPackage(uri:DocumentUri):Void {
		// editor selection can happen before server initialization
		if (determinePackage == null || !uri.isHaxeFile()) {
			latestActiveFilePackage = "";
			return;
		}
		determinePackage.onDeterminePackage({fsPath: uri.toFsPath().toString()}, null, result -> {
			latestActiveFilePackage = result.pack;
		}, error -> {
			latestActiveFilePackage = "";
		});
	}

	function publishDiagnostics(uri:DocumentUri) {
		if (diagnostics != null && config.user.enableDiagnostics) {
			diagnostics.publishDiagnostics(uri);
		}
	}

	function runMethod(params:{method:String, ?params:Any}, ?token:CancellationToken, resolve:Dynamic->Void, reject:ResponseError<NoData>->Void) {
		callHaxeMethod(cast params.method, params.params, token, function(response) {
			resolve(response);
			return null;
		}, function(error) {
			reject(new ResponseError(0, error));
		});
	}

	public function callHaxeMethod<P, R>(method:HaxeRequestMethod<P, Response<R>>, ?params:P, ?token:CancellationToken, callback:(result:R) -> Null<String>,
			errback:(error:String) -> Void) {
		final beforeCallTime = Date.now().getTime();
		haxeDisplayProtocol.sendRequest(cast method, params, token, function(response) {
			final arrivalTime = Date.now().getTime();
			if (!config.sendMethodResults) {
				callback(response.result);
				return;
			}

			final beforeProcessingTime = Date.now().getTime();
			final debugInfo:Null<String> = try {
				callback(response.result);
			} catch (e) {
				errback(e.toString());
				trace(e);
				trace(e.stack);
				null;
			}
			final afterProcessingTime = Date.now().getTime();
			final methodResult:MethodResult = {
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
			errback(if (error.data != null) error.data[0].message else "unknown error");
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
		if (includeDisplayArguments && config.displayArguments != null) {
			actualArgs = actualArgs.concat(config.displayArguments); // add arguments from the workspace settings
		}
		actualArgs.push("--display");
		actualArgs = actualArgs.concat(args); // finally, add given query args
		haxeServer.process(label, actualArgs, token, true, stdin, Processed(callback, errback));
	}

	public function startTimer(method:String) {
		final startTime = Date.now().getTime();
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

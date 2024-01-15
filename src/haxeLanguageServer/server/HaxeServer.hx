package haxeLanguageServer.server;

import haxe.DynamicAccess;
import haxe.Json;
import haxe.display.Protocol;
import haxe.display.Server.ServerMethods;
import haxe.io.Path;
import haxeLanguageServer.LanguageServerMethods.ServerAddress;
import haxeLanguageServer.helper.SemVer;
import haxeLanguageServer.server.HaxeConnection;
import js.lib.Promise;
import js.node.Buffer;
import js.node.ChildProcess;
import js.node.Net;
import js.node.net.Server;
import js.node.net.Socket.SocketEvent;
import jsonrpc.CancellationToken;
import sys.FileSystem;

using haxeLanguageServer.helper.StringHelper;

class HaxeServer {
	final context:Context;
	var haxeConnection:Null<HaxeConnection>;
	var requestsHead:Null<DisplayRequest>;
	var requestsTail:Null<DisplayRequest>;
	var currentRequest:Null<DisplayRequest>;
	var socketListener:Null<js.node.net.Server>;
	var starting:Bool = false;
	var stopProgressCallback:Null<() -> Void>;
	var startRequest:Null<() -> Void>;
	var crashes:Int = 0;
	var supportedMethods:Array<String> = [];

	public var haxeVersion(default, null) = new SemVer(0, 0, 0);
	public var protocolVersion(default, null) = new SemVer(0, 0, 0);

	public function new(context:Context) {
		this.context = context;
	}

	function checkHaxeVersion(haxePath:String, spawnOptions:ChildProcessSpawnSyncOptions) {
		inline function error(s) {
			context.sendShowMessage(Error, s);
			return false;
		}

		final checkRun = ChildProcess.spawnSync(haxePath, ["-version"], spawnOptions);
		if (checkRun.error != null) {
			if (checkRun.error.message.contains("ENOENT")) {
				if (haxePath == "haxe") { // default
					return error("Could not find Haxe in PATH. Is it installed?");
				} else {
					return error('Path to Haxe executable is not valid: \'$haxePath\'. Please check your settings.');
				}
			}
			return error('Error starting Haxe server: ${checkRun.error.message.clean()}');
		}

		var output = (checkRun.stderr : Buffer).toString().trim().clean();
		if (output == "") {
			output = (checkRun.stdout : Buffer).toString().trim().clean(); // haxe 4.0 prints -version output to stdout instead
		}

		if (checkRun.status != 0) {
			return error(if (output == "") {
				'`haxe -version` exited with error code ${checkRun.status}';
			} else {
				'Haxe version check failed: "$output"';
			});
		}

		final haxeVersion = SemVer.parse(output);
		if (haxeVersion == null) {
			return error("Error parsing Haxe version " + Json.stringify(output));
		} else {
			this.haxeVersion = haxeVersion;
		}
		final isVersionSupported = haxeVersion >= new SemVer(3, 4, 0);
		if (!isVersionSupported) {
			return error('Unsupported Haxe version! Minimum required: 3.4.0. Found: $haxeVersion.');
		}
		return true;
	}

	function mergeEnvs(from:DynamicAccess<String>, to:DynamicAccess<String>) {
		@:nullSafety(Off)
		for (key => value in from) {
			if (Sys.systemName() == "Windows") {
				// compare case-insensitive, but preserve the original casing
				for (initialKey in to.keys()) {
					if (key.toLowerCase() == initialKey.toLowerCase()) {
						key = initialKey;
						break;
					}
				}
			}
			to[key] = value;
		}
	}

	public function start(?callback:() -> Void) {
		// we still have requests in our queue that are not cancelable, such as a build - try again later
		if (hasNonCancellableRequests() || starting) {
			startRequest = callback;
			return;
		}

		supportedMethods = [];
		startRequest = null;
		stop();

		final config = context.config.displayServer;

		final env = new DynamicAccess();
		mergeEnvs(js.Node.process.env, env);
		mergeEnvs(config.env, env);

		final spawnOptions = {env: env, cwd: context.workspacePath.toString()};

		if (!checkHaxeVersion(config.path, spawnOptions)) {
			return;
		}
		starting = true;

		function onHaxeStarted(connection) {
			haxeConnection = connection;

			function onInitComplete() {
				stopProgress();
				buildCompletionCache();
				if (callback != null) {
					callback();
				}
			}

			context.callHaxeMethod(Methods.Initialize, {
				supportsResolve: true,
				exclude: context.config.user.exclude,
				maxCompletionItems: context.config.user.maxCompletionItems
			}, null, function(result) {
				final pre = result.haxeVersion.pre;
				if (result.haxeVersion.major == 4 && result.haxeVersion.minor == 0 && pre != null) {
					context.languageServerProtocol.sendNotification(LanguageServerMethods.DidDetectOldHaxeVersion, {
						haxe4Preview: true,
						version: haxeVersion.toString()
					});
				}
				protocolVersion = result.protocolVersion;
				supportedMethods = result.methods;
				configure();
				onInitComplete();
				return null;
			}, function(error) {
				// the "invalid format" error is expected for Haxe versions <= 4.0.0-preview.3
				if (error.startsWith("Error: Invalid format")) {
					trace("Haxe version does not support JSON-RPC, using legacy --display API.");
					context.languageServerProtocol.sendNotification(LanguageServerMethods.DidDetectOldHaxeVersion, {
						haxe4Preview: haxeVersion.major == 4,
						version: haxeVersion.toString()
					});
				} else {
					trace(error);
				}
				onInitComplete();
			});

			final displayPort = context.config.user.displayPort;
			final displayHost = context.config.user.displayHost ?? "127.0.0.1";
			if (socketListener == null && displayPort != null) {
				if (displayPort == "auto") {
					getAvailablePort(displayHost, 6000).then(startSocketServer);
				} else {
					startSocketServer({host: displayHost, port: displayPort});
				}
			} else {
				starting = false;
				checkRestart();
			}
		}

		var useSocket = config.useSocket;
		if (haxeVersion.major < 4) {
			useSocket = false;
		}
		if (haxeVersion.major == 4 && haxeVersion.minor == 0 && haxeVersion.pre != null) {
			useSocket = false;
		}
		if (FileSystem.exists(Path.join([context.workspacePath.toString(), ".haxerc"]))) {
			useSocket = false; // waiting on lix-pm/haxeshim#49
		}

		final startConnection = if (useSocket) SocketConnection.start else StdioConnection.start;
		trace("Haxe Path: " + config.path);
		spawnOptions.env["HAXE_COMPLETION_SERVER"] = "1";
		startConnection(config.path, config.arguments, spawnOptions, log, onMessage, onExit, onHaxeStarted);
	}

	function log(msg:String):Void {
		trace(msg);
		context.serverRecording.onServerLog(msg);
	}

	function configure() {
		context.callHaxeMethod(ServerMethods.Configure, {
			noModuleChecks: true,
			print: context.config.displayServer.print,
			populateCacheFromDisplay: context.config.user.populateCacheFromDisplay,
			legacyCompletion: context.config.user.useLegacyCompletion
		}, null, _ -> null, function(error) {
			trace("Error during " + ServerMethods.Configure + " " + error);
		});
	}

	function buildCompletionCache() {
		if (!context.config.user.buildCompletionCache || context.config.displayArguments == null) {
			return;
		}
		startProgress("Building Cache");

		// see vshaxe/haxe-language-server#44 for explanation
		final leadingArgs = ["--no-output", "--each", "--no-output"];

		process("cache build", leadingArgs.concat(context.config.displayArguments), null, true, null, Processed(function(_) {
			stopProgress();
			if (supports(ServerMethods.ReadClassPaths)) {
				readClassPaths();
			} else {
				trace("Done.");
			}
		}, function(error) {
			if (context.config.user.enableCompletionCacheWarning) {
				context.languageServerProtocol.sendNotification(LanguageServerMethods.CacheBuildFailed);
			}
			stopProgress();
			trace("Failed - try fixing the error(s) and restarting the language server:\n\n" + error.clean());
		}));
	}

	function readClassPaths() {
		startProgress("Parsing Classpaths");
		context.callHaxeMethod(ServerMethods.ReadClassPaths, null, null, function(result) {
			stopProgress();
			trace("Done.");
			if (result.files == null) {
				return null;
			}
			return result.files + " files";
		}, function(error) {
			stopProgress();
			trace("Failed - " + error.clean());
		});
	}

	function hasNonCancellableRequests():Bool {
		if (currentRequest != null && !currentRequest.cancellable)
			return true;

		var request = requestsHead;
		while (request != null) {
			if (!request.cancellable) {
				return true;
			}
			request = request.next;
		}

		return false;
	}

	// https://gist.github.com/mikeal/1840641#gistcomment-2337132
	function getAvailablePort(host:String, startingAt:Int):Promise<ServerAddress> {
		function getNextAvailablePort(currentPort:Int, cb:ServerAddress->Void) {
			final server = Net.createServer();
			server.listen(currentPort, host, () -> {
				server.once(ServerEvent.Close, cb.bind({host: host, port: currentPort}));
				server.close();
			});
			server.on(ServerEvent.Error, _ -> getNextAvailablePort(currentPort + 1, cb));
		}
		return new Promise((resolve, reject) -> getNextAvailablePort(startingAt, resolve));
	}

	public function startSocketServer(address:ServerAddress) {
		if (socketListener != null) {
			socketListener.close();
		}
		socketListener = Net.createServer(function(socket) {
			trace("Client connected");
			socket.on(SocketEvent.Data, function(data:Buffer) {
				final s = data.toString();
				final split = s.split("\n");
				split.pop(); // --connect passes extra \0
				function callback(result:DisplayResult) {
					switch result {
						case DResult(data):
							socket.write(data);
						case DCancelled:
					}
					socket.end();
					socket.destroy();
					trace("Client disconnected");
				}
				context.resetInvalidatedFiles();
				process("compilation", split, null, false, null, Raw(callback));
			});
			socket.on(SocketEvent.Error, function(err) {
				trace("Socket error: " + err);
			});
		});
		socketListener.listen(address.port, address.host);
		trace('Listening on port ${address.host}:${address.port}');
		context.languageServerProtocol.sendNotification(LanguageServerMethods.DidChangeDisplayPort, address);

		starting = false;
		checkRestart();
	}

	public function stop() {
		if (haxeConnection != null) {
			haxeConnection.kill();
			haxeConnection = null;
		}

		stopProgress();

		// cancel all callbacks
		var request = requestsHead;
		while (request != null) {
			request.cancel();
			request = request.next;
		}

		requestsHead = requestsTail = currentRequest = null;
		updateRequestQueue();
	}

	function startProgress(title:String) {
		stopProgress();
		stopProgressCallback = context.startProgress(title);
	}

	function stopProgress() {
		if (stopProgressCallback != null) {
			stopProgressCallback();
		}
		stopProgressCallback = null;
	}

	public function restart(reason:String, ?callback:() -> Void) {
		trace('Haxe server restart requested: $reason');
		start(function() {
			trace('Restarted Haxe server: $reason');
			if (callback != null) {
				callback();
			}
		});
	}

	function onExit(connection:HaxeConnection) {
		stopProgress();
		crashes++;
		if (crashes < 3) {
			restart("Haxe process was killed");
			return;
		}

		final haxeResponse = connection.getLastErrorOutput();

		// invalid compiler argument?
		final invalidOptionRegex = ~/unknown option [`'](.*?)'./;
		if (invalidOptionRegex.match(haxeResponse)) {
			final option = invalidOptionRegex.matched(1);
			context.sendShowMessage(Error,
				'Invalid compiler argument \'$option\' detected. Please verify "haxe.configurations" and "haxe.displayServer.arguments".');
			return;
		}

		context.languageServerProtocol.sendNotification(LanguageServerMethods.HaxeKeepsCrashing);
		trace("\nError message from the compiler:\n");
		trace(haxeResponse);
	}

	function onMessage(msg:String) {
		if (currentRequest != null) {
			final request = currentRequest;
			context.serverRecording.onServerMessage(request, msg);
			currentRequest = null;
			request.onData(msg);
			updateRequestQueue();
			checkQueue();
		}
	}

	public function process(label:String, args:Array<String>, ?token:CancellationToken, cancellable:Bool, ?stdin:String, handler:ResultHandler) {
		// create a request object
		final request = new DisplayRequest(label, args, token, cancellable, stdin, handler);

		// if the request is cancellable, set a cancel callback to remove request from queue
		if (token != null) {
			token.setCallback(function() {
				if (request == currentRequest)
					return; // currently processing requests can't be canceled

				context.serverRecording.onDisplayRequestCancelled(request);

				// remove from the queue
				if (request == requestsHead)
					requestsHead = request.next;
				if (request == requestsTail)
					requestsTail = request.prev;
				if (request.prev != null)
					request.prev.next = request.next;
				if (request.next != null)
					request.next.prev = request.prev;

				// notify about the cancellation
				request.cancel();
				updateRequestQueue();
			});
		}

		// add to the queue
		if (requestsHead == null || requestsTail == null) {
			requestsHead = requestsTail = request;
		} else {
			requestsTail.next = request;
			request.prev = requestsTail;
			requestsTail = request;
		}

		if (currentRequest != null) {
			context.serverRecording.onDisplayRequestQueued(request);
		}

		// process the queue
		checkQueue();
		updateRequestQueue();
	}

	function checkRestart() {
		if (startRequest != null) {
			start(startRequest);
			return;
		}
	}

	function checkQueue() {
		checkRestart();

		// there's a currently processing request, wait and don't send another one to Haxe
		if (currentRequest != null)
			return;

		// pop the first request still in queue, set it as current and send to Haxe
		if (requestsHead != null && haxeConnection != null) {
			currentRequest = requestsHead;
			requestsHead = currentRequest.next;
			updateRequestQueue();
			context.serverRecording.onDisplayRequest(currentRequest);
			haxeConnection.send(currentRequest.prepareBody());
		}
	}

	public function supports<P, R>(method:HaxeRequestMethod<P, R>) {
		return supportedMethods.contains(method);
	}

	function updateRequestQueue() {
		if (!context.config.sendMethodResults) {
			return;
		}
		final queue = [];
		var request = currentRequest;
		while (request != null) {
			queue.push(request.label);
			request = request.next;
		}
		context.languageServerProtocol.sendNotification(LanguageServerMethods.DidChangeRequestQueue, {queue: queue});
	}
}

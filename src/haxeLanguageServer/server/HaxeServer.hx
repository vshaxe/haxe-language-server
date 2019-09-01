package haxeLanguageServer.server;

import haxe.Json;
import haxe.display.Server.ServerMethods;
import haxe.display.Protocol;
import js.lib.Promise;
import js.node.Net;
import js.node.net.Socket;
import js.node.net.Server;
import js.node.child_process.ChildProcess as ChildProcessObject;
import js.node.child_process.ChildProcess.ChildProcessEvent;
import js.node.Buffer;
import js.node.ChildProcess;
import js.node.stream.Readable;
import js.node.stream.Writable;
import jsonrpc.CancellationToken;
import haxeLanguageServer.helper.SemVer;

class HaxeServer {
	final context:Context;
	var proc:Null<ChildProcessObject>;
	var commandInput:IWritable;
	var buffer:MessageBuffer;
	var nextMessageLength:Int;
	var requestsHead:Null<DisplayRequest>;
	var requestsTail:Null<DisplayRequest>;
	var currentRequest:Null<DisplayRequest>;
	var socketListener:Null<js.node.net.Server>;
	var startingSocketListener:Bool = false;
	var stopProgressCallback:Null<Void->Void>;
	var startRequest:Null<Void->Void>;
	var crashes:Int = 0;
	var supportedMethods:Array<String> = [];

	public var haxeVersion(default, null):Null<SemVer>;
	public var protocolVersion(default, null):Null<SemVer>;

	public function new(context:Context) {
		this.context = context;
	}

	static final reTrailingNewline = ~/\r?\n$/;

	function checkHaxeVersion(haxePath, spawnOptions) {
		inline function error(s) {
			context.sendShowMessage(Error, s);
			return false;
		}

		var checkRun = ChildProcess.spawnSync(haxePath, ["-version"], spawnOptions);
		if (checkRun.error != null) {
			if (checkRun.error.message.contains("ENOENT")) {
				if (haxePath == "haxe") // default
					return error("Could not find Haxe in PATH. Is it installed?");
				else
					return error('Path to Haxe executable is not valid: \'$haxePath\'. Please check your settings.');
			}
			return error('Error starting Haxe server: ${checkRun.error}');
		}

		var output = (checkRun.stderr : Buffer).toString().trim();
		if (output == "")
			output = (checkRun.stdout : Buffer).toString().trim(); // haxe 4.0 prints -version output to stdout instead

		if (checkRun.status != 0) {
			return error(if (output == "") {
				'`haxe -version` exited with error code ${checkRun.status}';
			} else {
				'Haxe version check failed: "$output"';
			});
		}

		haxeVersion = SemVer.parse(output);
		if (haxeVersion == null)
			return error("Error parsing Haxe version " + Json.stringify(output));

		var isVersionSupported = haxeVersion >= new SemVer(3, 4, 0);
		if (!isVersionSupported)
			return error('Unsupported Haxe version! Minimum required: 3.4.0. Found: $haxeVersion.');
		return true;
	}

	public function start(?callback:Void->Void) {
		// we still have requests in our queue that are not cancelable, such as a build - try again later
		if (hasNonCancellableRequests() || startingSocketListener) {
			startRequest = callback;
			return;
		}

		supportedMethods = [];
		startRequest = null;
		stop();

		var config = context.config.displayServer;

		var env = new haxe.DynamicAccess();
		for (key => value in js.Node.process.env)
			env[key] = value;
		for (key => value in config.env)
			env[key] = value;
		var spawnOptions = {env: env, cwd: context.workspacePath.toString()};

		if (!checkHaxeVersion(config.path, spawnOptions)) {
			return;
		}

		buffer = new MessageBuffer();
		nextMessageLength = -1;

		function onConnected(socket:Socket) {
			trace("Haxe connected!");

			socket.on(ReadableEvent.Data, onData);
			commandInput = socket;

			function onInitComplete() {
				stopProgress();
				buildCompletionCache();
				if (callback != null)
					callback();
			}

			stopProgressCallback = context.startProgress("Initializing Haxe/JSON-RPC protocol");
			context.callHaxeMethod(Methods.Initialize, {supportsResolve: true, exclude: context.config.user.exclude, maxCompletionItems: 1000}, null,
				result -> {
					var pre = result.haxeVersion.pre;
					if (result.haxeVersion.major == 4 && (pre.startsWith("preview.") || pre == "rc.1" || pre == "rc.2")) {
						context.languageServerProtocol.sendNotification(LanguageServerMethods.DidDetectOldPreview, {preview: result.haxeVersion.pre});
					}
					protocolVersion = result.protocolVersion;
					supportedMethods = result.methods;
					configure();
					onInitComplete();
					return null;
				}, error -> {
				// the "invalid format" error is expected for Haxe versions <= 4.0.0-preview.3
				if (error.startsWith("Error: Invalid format")) {
					trace("Haxe version does not support JSON-RPC, using legacy --display API.");
					if (haxeVersion.major == 4) {
						context.languageServerProtocol.sendNotification(LanguageServerMethods.DidDetectOldPreview);
					}
				} else {
					trace(error);
				}
				onInitComplete();
			});

			var displayPort = context.config.user.displayPort;
			if (socketListener == null && displayPort != null) {
				startingSocketListener = true;
				if (displayPort == "auto") {
					getAvailablePort(6000).then(startSocketServer);
				} else {
					startSocketServer(displayPort);
				}
			}
		}

		var server = Net.createServer(onConnected);
		server.listen(0, function() {
			var port = server.address().port;
			proc = ChildProcess.spawn(config.path, config.arguments.concat(["--server-connect", '127.0.0.1:$port']), spawnOptions);
			proc.stdout.on(ReadableEvent.Data, onStdout);
			proc.stderr.on(ReadableEvent.Data, onStdout);
			proc.on(ChildProcessEvent.Exit, onExit);
		});
	}

	function configure() {
		context.callHaxeMethod(ServerMethods.Configure, {noModuleChecks: true, print: context.config.displayServer.print}, null, _ -> null, error -> {
			trace("Error during " + ServerMethods.Configure + " " + error);
		});
	}

	function buildCompletionCache() {
		if (!context.config.user.buildCompletionCache || context.config.displayArguments == null)
			return;

		startCompletionInitializationProgress("Building Cache");
		process("cache build", context.config.displayArguments.concat(["--no-output"]), null, true, null, Processed(function(_) {
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
			trace("Failed - try fixing the error(s) and restarting the language server:\n\n" + error);
		}));
	}

	function readClassPaths() {
		startCompletionInitializationProgress("Parsing Classpaths");
		context.callHaxeMethod(ServerMethods.ReadClassPaths, null, null, result -> {
			stopProgress();
			trace("Done.");
			if (result.files == null) {
				return null;
			}
			return result.files + " files";
		}, error -> {
			stopProgress();
			trace("Failed - " + error);
		});
	}

	function startCompletionInitializationProgress(message:String) {
		stopProgressCallback = context.startProgress(message);
		trace(message + "...");
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
	function getAvailablePort(startingAt:Int):Promise<Int> {
		function getNextAvailablePort(currentPort:Int, cb:Int->Void) {
			var server = Net.createServer();
			server.listen(currentPort, "localhost", () -> {
				server.once(ServerEvent.Close, cb.bind(currentPort));
				server.close();
			});
			server.on(ServerEvent.Error, _ -> getNextAvailablePort(currentPort + 1, cb));
		}

		return new Promise((resolve, reject) -> getNextAvailablePort(startingAt, resolve));
	}

	public function startSocketServer(port:Int) {
		if (socketListener != null) {
			socketListener.close();
		}
		socketListener = Net.createServer(function(socket) {
			trace("Client connected");
			socket.on(SocketEvent.Data, function(data:Buffer) {
				var s = data.toString();
				var split = s.split("\n");
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
				process("compilation", split, null, false, null, Raw(callback));
			});
			socket.on(SocketEvent.Error, function(err) {
				trace("Socket error: " + err);
			});
		});
		socketListener.listen(port, "localhost");
		trace('Listening on port $port');
		context.languageServerProtocol.sendNotification(LanguageServerMethods.DidChangeDisplayPort, {port: port});

		startingSocketListener = false;
		checkRestart();
	}

	public function stop() {
		if (proc != null) {
			proc.removeAllListeners();
			proc.kill();
			proc = null;
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

	function stopProgress() {
		if (stopProgressCallback != null) {
			stopProgressCallback();
		}
		stopProgressCallback = null;
	}

	public function restart(reason:String, ?callback:Void->Void) {
		trace('Haxe server restart requested: $reason');
		start(function() {
			trace('Restarted Haxe server: $reason');
			if (callback != null)
				callback();
		});
	}

	function onExit(_, _) {
		crashes++;
		if (crashes < 3) {
			restart("Haxe process was killed");
			return;
		}

		var haxeResponse = buffer.getContent();

		// invalid compiler argument?
		var invalidOptionRegex = ~/unknown option `(.*?)'./;
		if (invalidOptionRegex.match(haxeResponse)) {
			var option = invalidOptionRegex.matched(1);
			context.sendShowMessage(Error,
				'Invalid compiler argument \'$option\' detected. Please verify "haxe.configurations" and "haxe.displayServer.arguments".');
			return;
		}

		context.languageServerProtocol.sendNotification(LanguageServerMethods.HaxeKeepsCrashing);
		trace("\nError message from the compiler:\n");
		trace(haxeResponse);
	}

	function onStdout(buf:Buffer) {
		trace(reTrailingNewline.replace(buf.toString(), ""));
	}

	function onData(data:Buffer) {
		buffer.append(data);
		while (true) {
			if (nextMessageLength == -1) {
				var length = buffer.tryReadLength();
				if (length == -1)
					return;
				nextMessageLength = length;
			}
			var msg = buffer.tryReadContent(nextMessageLength);
			if (msg == null)
				return;
			nextMessageLength = -1;
			if (currentRequest != null) {
				var request = currentRequest;
				currentRequest = null;
				request.onData(msg);
				updateRequestQueue();
				checkQueue();
			}
		}
	}

	public function process(label:String, args:Array<String>, ?token:CancellationToken, cancellable:Bool, ?stdin:String, handler:ResultHandler) {
		// create a request object
		var request = new DisplayRequest(label, args, token, cancellable, stdin, handler);

		// if the request is cancellable, set a cancel callback to remove request from queue
		if (token != null) {
			token.setCallback(function() {
				if (request == currentRequest)
					return; // currently processing requests can't be canceled

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
		if (requestsHead == null) {
			requestsHead = requestsTail = request;
		} else {
			requestsTail.next = request;
			request.prev = requestsTail;
			requestsTail = request;
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
		if (requestsHead != null && proc != null) {
			currentRequest = requestsHead;
			requestsHead = currentRequest.next;
			updateRequestQueue();
			commandInput.write(currentRequest.prepareBody());
		}
	}

	public function supports<P, R>(method:HaxeRequestMethod<P, R>) {
		return supportedMethods.contains(method);
	}

	function updateRequestQueue() {
		if (!context.config.sendMethodResults) {
			return;
		}
		var queue = [];
		var request = currentRequest;
		while (request != null) {
			queue.push(request.label);
			request = request.next;
		}
		context.languageServerProtocol.sendNotification(LanguageServerMethods.DidChangeRequestQueue, {queue: queue});
	}
}

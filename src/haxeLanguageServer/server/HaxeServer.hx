package haxeLanguageServer.server;

import haxe.Json;
import js.Promise;
import js.node.Net;
import js.node.net.Socket;
import js.node.net.Server;
import js.node.Buffer;
import js.node.ChildProcess;
import jsonrpc.CancellationToken;
import haxeLanguageServer.helper.SemVer;
import haxeLanguageServer.protocol.Server.ServerMethods;
import haxeLanguageServer.protocol.Protocol;

class HaxeServer {
	final context:Context;
	var socketListener:Null<js.node.net.Server>;
	var stopProgressCallback:Null<Void->Void>;
	var startRequest:Null<Void->Void>;
	var crashes:Int = 0;
	var supportedMethods:Array<String> = [];

	public var version(default, null):Null<SemVer>;

	public function new(context:Context) {
		this.context = context;
	}

	static final reTrailingNewline = ~/\r?\n$/;

	public function start(?callback:Void->Void) {
		supportedMethods = [];
		startRequest = null;
		stop();

		inline function error(s)
			context.sendShowMessage(Error, s);

		var config = context.config.displayServer;

		var env = new haxe.DynamicAccess();
		for (key => value in js.Node.process.env)
			env[key] = value;
		for (key => value in config.env)
			env[key] = value;

		var haxePath = config.path;
		var checkRun = ChildProcess.spawnSync(haxePath, ["-version"], {env: env});
		if (checkRun.error != null) {
			if (checkRun.error.message.indexOf("ENOENT") >= 0) {
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

		version = SemVer.parse(output);
		if (version == null)
			return error("Error parsing Haxe version " + haxe.Json.stringify(output));

		var isVersionSupported = version >= new SemVer(3, 4, 0);
		if (!isVersionSupported)
			return error('Unsupported Haxe version! Minimum required: 3.4.0. Found: $version.');

		function onInitComplete() {
			stopProgress();
			buildCompletionCache();
			if (callback != null)
				callback();
		}

		stopProgressCallback = context.startProgress("Initializing Haxe/JSON-RPC protocol");
		context.callHaxeMethod(Methods.Initialize, {supportsResolve: true}, null, result -> {
			if (result.haxeVersion.major == 4 && result.haxeVersion.pre.startsWith("preview.")) {
				context.languageServerProtocol.sendNotification(LanguageServerMethods.DidDetectOldPreview, {preview: result.haxeVersion.pre});
			}
			supportedMethods = result.methods;
			configure();
			onInitComplete();
			return null;
		}, error -> {
			// the "invalid format" error is expected for Haxe versions <= 4.0.0-preview.3
			if (error.startsWith("Error: Invalid format")) {
				trace("Haxe version does not support JSON-RPC, using legacy --display API.");
				if (version.major == 4) {
					context.languageServerProtocol.sendNotification(LanguageServerMethods.DidDetectOldPreview);
				}
			} else {
				trace(error);
			}
			onInitComplete();
		});

		var displayPort = context.config.user.displayPort;
		if (socketListener == null && displayPort != null) {
			if (displayPort == "auto") {
				getAvailablePort(6000).then(startSocketServer);
			} else {
				startSocketServer(displayPort);
			}
		}
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
			context.languageServerProtocol.sendNotification(LanguageServerMethods.CacheBuildFailed);
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
					switch (result) {
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
		context.sendLogMessage(Log, 'Listening on port $port');
		context.languageServerProtocol.sendNotification(LanguageServerMethods.DidChangeDisplayPort, {port: port});
	}

	public function stop() {
		stopProgress();
	}

	function stopProgress() {
		if (stopProgressCallback != null) {
			stopProgressCallback();
		}
		stopProgressCallback = null;
	}

	public function restart(reason:String, ?callback:Void->Void) {
		context.sendLogMessage(Log, 'Haxe server restart requested: $reason');
		start(function() {
			context.sendLogMessage(Log, 'Restarted Haxe server: $reason');
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

		// var haxeResponse = buffer.getContent();

		// // invalid compiler argument?
		// var invalidOptionRegex = ~/unknown option `(.*?)'./;
		// if (invalidOptionRegex.match(haxeResponse)) {
		// 	var option = invalidOptionRegex.matched(1);
		// 	context.sendShowMessage(Error, 'Invalid compiler argument \'$option\' detected. '
		// 		+ 'Please verify "haxe.displayConfigurations" and "haxe.displayServer.arguments".');
		// 	return;
		// }

		// context.sendShowMessage(Error,
		// 	"Haxe process has crashed 3 times, not attempting any more restarts. Please check the output channel for the full error.");
		// trace("\nError message from the compiler:\n");
		// trace(haxeResponse);
	}

	public function process(label:String, args:Array<String>, ?token:CancellationToken, cancellable:Bool, ?stdin:String, handler:ResultHandler) {
	}

	public function supports<P, R>(method:HaxeRequestMethod<P, R>) {
		return supportedMethods.indexOf(method) != -1;
	}
}

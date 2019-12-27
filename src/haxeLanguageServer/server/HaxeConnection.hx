package haxeLanguageServer.server;

import js.node.Buffer;
import js.node.ChildProcess;
import js.node.Net;
import js.node.child_process.ChildProcess as ChildProcessObject;
import js.node.child_process.ChildProcess.ChildProcessEvent;
import js.node.net.Server.ServerEvent;
import js.node.net.Socket;
import js.node.stream.Readable;

class HaxeConnection {
	static final reTrailingNewline = ~/\r?\n$/;

	final buffer = new MessageBuffer();
	final onMessage:String->Void;
	final process:ChildProcessObject;
	var nextMessageLength = -1;

	function new(process, onMessage, onExit) {
		this.process = process;
		this.onMessage = onMessage;
		process.on(ChildProcessEvent.Exit, (_, _) -> onExit(this));
	}

	public function send(data:Buffer) {}

	public function kill() {
		process.removeAllListeners();
		process.kill();
	}

	public function getLastErrorOutput():String {
		return "";
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
			onMessage(msg);
		}
	}
}

class StdioConnection extends HaxeConnection {
	function new(process, onMessage, onExit) {
		super(process, onMessage, onExit);
		process.stdout.on(ReadableEvent.Data, onStdout);
		process.stderr.on(ReadableEvent.Data, onData);
	}

	override function send(data:Buffer) {
		process.stdin.write(data);
	}

	override function getLastErrorOutput():String {
		return buffer.getContent();
	}

	public static function start(path:String, arguments:Array<String>, spawnOptions:ChildProcessSpawnOptions, onMessage:String->Void,
			onExit:HaxeConnection->Void, callback:HaxeConnection->Void) {
		trace("Using --wait stdio");
		var process = ChildProcess.spawn(path, arguments.concat(["--wait", "stdio"]), spawnOptions);
		callback(new StdioConnection(process, onMessage, onExit));
	}
}

class SocketConnection extends HaxeConnection {
	var socket:Null<Socket>;
	var lastErrorOutput:String = "";

	function new(process, onMessage, onExit) {
		super(process, onMessage, onExit);
		process.stdout.on(ReadableEvent.Data, onStdout);
		process.stderr.on(ReadableEvent.Data, onStderr);
	}

	function setup(socket:Socket) {
		this.socket = socket;
		socket.on(ReadableEvent.Data, onData);
	}

	override function send(data:Buffer) {
		socket.write(data);
	}

	override function kill() {
		if (socket != null) {
			// the socket will get ECONNRESET and nodejs will throw if we don't handle it as an event
			socket.on(ReadableEvent.Error, function(_) {});
		}
		super.kill();
	}

	function onStderr(buf:Buffer) {
		lastErrorOutput = buf.toString();
		trace(HaxeConnection.reTrailingNewline.replace(lastErrorOutput, ""));
	}

	override function getLastErrorOutput():String {
		return lastErrorOutput;
	}

	public static function start(path:String, arguments:Array<String>, spawnOptions:ChildProcessSpawnOptions, onMessage:String->Void,
			onExit:HaxeConnection->Void, callback:HaxeConnection->Void) {
		trace("Using --server-connect");
		var server = Net.createServer();
		server.listen(0, function() {
			var port = server.address().port;
			var process = ChildProcess.spawn(path, arguments.concat(["--server-connect", '127.0.0.1:$port']), spawnOptions);
			var connection = new SocketConnection(process, onMessage, onExit);
			server.on(ServerEvent.Connection, function(socket) {
				trace("Haxe connected!");
				server.close();
				connection.setup(socket);
				callback(connection);
			});
		});
	}
}

package haxeLanguageServer.server;

import js.node.Buffer;
import jsonrpc.CancellationToken;

class DisplayRequest {
	public final label:String;
	public final cancellable:Bool;
	public final creationTime:Float;
	// these are used for the queue
	public var prev:Null<DisplayRequest>;
	public var next:Null<DisplayRequest>;

	final args:Array<String>;
	final token:Null<CancellationToken>;
	final stdin:Null<String>;
	final handler:ResultHandler;

	static final stdinSepBuf = Buffer.alloc(1, 1);

	public function new(label:String, args:Array<String>, ?token:CancellationToken, cancellable:Bool, ?stdin:String, handler:ResultHandler) {
		this.label = label;
		this.args = args;
		this.token = token;
		this.cancellable = cancellable;
		this.stdin = stdin;
		this.handler = handler;
		this.creationTime = Date.now().getTime();
	}

	public function prepareBody():Buffer {
		if (stdin != null) {
			args.push("-D");
			args.push("display-stdin");
		}

		final lenBuf = Buffer.alloc(4);
		final chunks = [lenBuf];
		var length = 0;
		for (arg in args) {
			final buf = Buffer.from(arg + "\n");
			chunks.push(buf);
			length += buf.length;
		}

		if (stdin != null) {
			chunks.push(stdinSepBuf);
			final buf = Buffer.from(stdin);
			chunks.push(buf);
			length += buf.length + stdinSepBuf.length;
		}

		lenBuf.writeInt32LE(length, 0);

		return Buffer.concat(chunks, length + 4);
	}

	public inline function cancel() {
		switch handler {
			case Raw(callback) | Processed(callback, _):
				callback(DCancelled);
		}
	}

	public function onData(data:String) {
		if (token != null && token.canceled)
			return cancel();

		switch handler {
			case Raw(callback):
				callback(DResult(data));
			case Processed(callback, errback):
				processResult(data, callback, errback);
		}
	}

	function processResult(data:String, callback:DisplayResult->Void, errback:(error:String) -> Void) {
		final buf = new StringBuf();
		var hasError = false;
		for (line in data.split("\n")) {
			switch line.fastCodeAt(0) {
				case 0x01: // print
					trace("Haxe print:\n" + line.substring(1).replace("\x01", "\n"));
				case 0x02: // error
					hasError = true;
				default:
					buf.add(line);
					buf.addChar("\n".code);
			}
		}

		final data = buf.toString().trim();

		if (hasError)
			return errback(data);

		try {
			callback(DResult(data));
		} catch (e) {
			errback(jsonrpc.ErrorUtils.errorToString(e, "Exception while handling Haxe completion response: "));
		}
	}
}

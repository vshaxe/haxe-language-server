package haxeLanguageServer.server;

import js.node.Buffer;

class MessageBuffer {
	static inline final DEFAULT_SIZE = 8192;

	var index:Int;
	var buffer:Buffer;

	public function new() {
		index = 0;
		buffer = Buffer.alloc(DEFAULT_SIZE);
	}

	public function append(chunk:Buffer):Void {
		if (buffer.length - index >= chunk.length) {
			chunk.copy(buffer, index, 0, chunk.length);
		} else {
			final newSize = (Math.ceil((index + chunk.length) / DEFAULT_SIZE) + 1) * DEFAULT_SIZE;
			if (index == 0) {
				buffer = Buffer.alloc(newSize);
				chunk.copy(buffer, 0, 0, chunk.length);
			} else {
				buffer = Buffer.concat([buffer.slice(0, index), chunk], newSize);
			}
		}
		index += chunk.length;
	}

	public function tryReadLength():Int {
		if (index < 4)
			return -1;
		final length = buffer.readInt32LE(0);
		buffer = buffer.slice(4);
		index -= 4;
		return length;
	}

	public function tryReadContent(length:Int):Null<String> {
		if (index < length)
			return null;
		final result = buffer.toString("utf-8", 0, length);
		final nextStart = length;
		buffer.copy(buffer, 0, nextStart);
		index -= nextStart;
		return result;
	}

	public function getContent():String {
		return buffer.toString("utf-8", 0, index);
	}
}

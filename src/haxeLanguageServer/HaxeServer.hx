package haxeLanguageServer;

import js.node.child_process.ChildProcess as ChildProcessObject;
import js.node.child_process.ChildProcess.ChildProcessEvent;
import js.node.Buffer;
import js.node.ChildProcess;
import js.node.stream.Readable;
import jsonrpc.CancellationToken;
using StringTools;

class HaxeServer {
    var proc:ChildProcessObject;
    var version:Array<Int>;
    static var reVersion = ~/^(\d+)\.(\d+)\.(\d+)(?:\s.*)?$/;

    var buffer:MessageBuffer;
    var nextMessageLength:Int;
    var callbacks:Array<String->Void>;
    var context:Context;

    public function new(context:Context) {
        callbacks = [];
        this.context = context;
    }

    public function start(token:CancellationToken, callback:String->Void) {
        stop();
        proc = ChildProcess.spawn("haxe", ["--wait", "stdio"]);
        buffer = new MessageBuffer();
        nextMessageLength = -1;
        proc.stdout.on(ReadableEvent.Data, function(buf:Buffer) context.protocol.sendVSHaxeLog(buf.toString()));
        proc.stderr.on(ReadableEvent.Data, onData);
        proc.on(ChildProcessEvent.Exit, onExit);
        process(["-version"], token, null, function(data) {
            if (!reVersion.match(data))
                return callback("Error parsing haxe version " + data);

            var major = Std.parseInt(reVersion.matched(1));
            var minor = Std.parseInt(reVersion.matched(2));
            var patch = Std.parseInt(reVersion.matched(3));
            if (major < 3 || minor < 3) {
                callback("Unsupported Haxe version! Minimum version required: 3.3.0");
            } else {
                version = [major, minor, patch];
                callback(null);
            }
        }, callback);
    }

    public function stop() {
        if (proc != null) {
            proc.removeAllListeners();
            proc.kill();
            proc = null;
        }
    }

    function onExit(_, _) {
        context.protocol.sendVSHaxeLog("Haxe process was killed, restarting...\n");
        proc.removeAllListeners();
        start(new CancellationTokenSource().token, function(error) {
            if (error != null)
                context.protocol.sendShowMessage({type: Error, message: error});
        });
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
            var cb = callbacks.shift();
            if (cb != null)
                cb(msg);
        }
    }

    static var stdinSepBuf = new Buffer([1]);

    public function process(args:Array<String>, token:CancellationToken, stdin:String, callback:String->Void, errback:String->Void) {
        if (stdin != null) {
            args.push("-D");
            args.push("display-stdin");
        }

        var chunks = [];
        var length = 0;
        for (arg in args) {
            var buf = new Buffer(arg + "\n");
            chunks.push(buf);
            length += buf.length;
        }

        if (stdin != null) {
            chunks.push(stdinSepBuf);
            var buf = new Buffer(stdin);
            chunks.push(buf);
            length += buf.length + stdinSepBuf.length;
        }

        var lenBuf = new Buffer(4);
        lenBuf.writeInt32LE(length, 0);
        proc.stdin.write(lenBuf);

        proc.stdin.write(Buffer.concat(chunks, length));

        callbacks.push(function(data) {
            if (token.canceled)
                return callback(null);

            var buf = new StringBuf();
            var hasError = false;
            for (line in data.split("\n")) {
                switch (line.fastCodeAt(0)) {
                    case 0x01: // print
                        trace("Haxe print:\n" + line.substring(1).replace("\x01", "\n"));
                    case 0x02: // error
                        hasError = true;
                    default:
                        buf.add(line);
                        buf.addChar("\n".code);
                }
            }

            var data = buf.toString().trim();

            if (hasError)
                return errback("Error from haxe server: " + data);

            try {
                callback(data);
            } catch (e:Dynamic) {
                errback(jsonrpc.ErrorUtils.errorToString(e, "Exception while handling haxe completion response: "));
            }
        });
    }
}



private class MessageBuffer {
    static inline var DEFAULT_SIZE = 8192;

    var index:Int;
    var buffer:Buffer;

    public function new() {
        index = 0;
        buffer = new Buffer(DEFAULT_SIZE);
    }

    public function append(chunk:Buffer):Void {
        if (buffer.length - index >= chunk.length) {
            chunk.copy(buffer, index, 0, chunk.length);
        } else {
            var newSize = (Math.ceil((index + chunk.length) / DEFAULT_SIZE) + 1) * DEFAULT_SIZE;
            if (index == 0) {
                buffer = new Buffer(newSize);
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
        var length = buffer.readInt32LE(0);
        buffer = buffer.slice(4);
        index -= 4;
        return length;
    }

    public function tryReadContent(length:Int):String {
        if (index < length)
            return null;
        var result = buffer.toString("utf-8", 0, length);
        var nextStart = length;
        buffer.copy(buffer, 0, nextStart);
        index -= nextStart;
        return result;
    }
}

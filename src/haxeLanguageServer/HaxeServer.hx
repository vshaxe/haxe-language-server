package haxeLanguageServer;

import js.node.child_process.ChildProcess as ChildProcessObject;
import js.node.child_process.ChildProcess.ChildProcessEvent;
import js.node.Buffer;
import js.node.ChildProcess;
import js.node.stream.Readable;
import jsonrpc.CancellationToken;
using StringTools;

private class DisplayRequest {
    // these are used for the queue
    public var prev:DisplayRequest;
    public var next:DisplayRequest;

    var token:CancellationToken;
    var args:Array<String>;
    var stdin:String;
    var callback:String->Void;
    var errback:String->Void;

    static var stdinSepBuf = new Buffer([1]);

    public function new(token:CancellationToken, args:Array<String>, stdin:String, callback:String->Void, errback:String->Void) {
        this.token = token;
        this.args = args;
        this.stdin = stdin;
        this.callback = callback;
        this.errback = errback;
    }

    public function prepareBody():Buffer {
        if (stdin != null) {
            args.push("-D");
            args.push("display-stdin");
        }

        var lenBuf = new Buffer(4);
        var chunks = [lenBuf];
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

        lenBuf.writeInt32LE(length, 0);

        return Buffer.concat(chunks, length + 4);
    }

    public function processResult(data:String) {
        if (data == null || (token != null && token.canceled))
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
        } catch (e:Any) {
            errback(jsonrpc.ErrorUtils.errorToString(e, "Exception while handling haxe completion response: "));
        }
    }
}

class HaxeServer {
    var proc:ChildProcessObject;
    var version:Array<Int>;
    static var reVersion = ~/^(\d+)\.(\d+)\.(\d+)(?:\s.*)?$/;

    var buffer:MessageBuffer;
    var nextMessageLength:Int;
    var context:Context;

    var requestsHead:DisplayRequest;
    var requestsTail:DisplayRequest;
    var currentRequest:DisplayRequest;

    public function new(context:Context) {
        this.context = context;
    }

    public function start(callback:Void->Void) {
        stop();

        var args = context.displayServerConfig.arguments.concat(["--wait", "stdio"]);

        var env = new haxe.DynamicAccess();
        for (key in js.Node.process.env.keys())
            env[key] = js.Node.process.env[key];
        for (key in context.displayServerConfig.env.keys())
            env[key] = context.displayServerConfig.env[key];

        proc = ChildProcess.spawn(context.displayServerConfig.haxePath, args, {env: env});

        buffer = new MessageBuffer();
        nextMessageLength = -1;
        proc.stdout.on(ReadableEvent.Data, function(buf:Buffer) context.protocol.sendNotification(VshaxeMethods.Log, buf.toString()));
        proc.stderr.on(ReadableEvent.Data, onData);

        proc.on(ChildProcessEvent.Exit, onExit);

        inline function error(s) context.protocol.sendShowMessage({type: Error, message: s});

        process(["-version"], null, null, function(data) {
            if (!reVersion.match(data))
                return error("Error parsing haxe version " + data);

            var major = Std.parseInt(reVersion.matched(1));
            var minor = Std.parseInt(reVersion.matched(2));
            var patch = Std.parseInt(reVersion.matched(3));
            if (major < 3 || minor < 3) {
                error("Unsupported Haxe version! Minimum version required: 3.3.0");
            } else {
                version = [major, minor, patch];
                callback();
            }
        }, function(errorMessage) error(errorMessage));
    }

    public function stop() {
        if (proc != null) {
            proc.removeAllListeners();
            proc.kill();
            proc = null;
        }

        // cancel all callbacks
        var request = requestsHead;
        while (request != null) {
            request.processResult(null);
            request = request.next;
        }

        requestsHead = requestsTail = currentRequest = null;
    }

    public function restart(reason:String) {
        context.protocol.sendNotification(VshaxeMethods.Log, 'Restarting Haxe completion server: $reason\n');
        start(function() {});
    }

    function onExit(_, _) {
        restart("Haxe process was killed");
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
                request.processResult(msg);
                checkQueue();
            }
        }
    }

    public function process(args:Array<String>, token:CancellationToken, stdin:String, callback:String->Void, errback:String->Void) {
        // create a request object
        var request = new DisplayRequest(token, args, stdin, callback, errback);

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
    }

    function checkQueue() {
        // there's a currently processing request, wait and don't send another one to Haxe
        if (currentRequest != null)
            return;

        // pop the first request still in queue, set it as current and send to Haxe
        if (requestsHead != null) {
            currentRequest = requestsHead;
            requestsHead = currentRequest.next;
            proc.stdin.write(currentRequest.prepareBody());
        }
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

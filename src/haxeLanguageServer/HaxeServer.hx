package haxeLanguageServer;

import js.Promise;
import js.node.Net;
import js.node.net.Socket;
import js.node.net.Server;
import js.node.child_process.ChildProcess as ChildProcessObject;
import js.node.child_process.ChildProcess.ChildProcessEvent;
import js.node.Buffer;
import js.node.ChildProcess;
import js.node.stream.Readable;
import jsonrpc.CancellationToken;
import haxeLanguageServer.helper.SemVer;

enum DisplayResult {
    DCancelled;
    DResult(msg:String);
}

private class DisplayRequest {
    // these are used for the queue
    public var prev:DisplayRequest;
    public var next:DisplayRequest;

    var token:CancellationToken;
    var args:Array<String>;
    var stdin:String;
    var callback:DisplayResult->Void;
    var errback:String->Void;
    public var socket:Null<Socket>;

    static var stdinSepBuf = new Buffer([1]);

    public function new(token:CancellationToken, args:Array<String>, stdin:String, callback:DisplayResult->Void, errback:String->Void, socket) {
        this.token = token;
        this.args = args;
        this.stdin = stdin;
        this.callback = callback;
        this.errback = errback;
        this.socket = socket;
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

    public inline function cancel() {
        callback(DCancelled);
    }

    public function processResult(data:String) {
        if (token != null && token.canceled)
            return callback(DCancelled);

        var buf = new StringBuf();
        var hasError = false;
        for (line in data.split("\n")) {
            switch (line.fastCodeAt(0)) {
                case 0x01: // print
                    var line = line.substring(1).replace("\x01", "\n");
                    if (socket != null) {
                        socket.write(line);
                    } else {
                        trace("Haxe print:\n" + line);
                    }
                case 0x02: // error
                    hasError = true;
                default:
                    buf.add(line);
                    buf.addChar("\n".code);
            }
        }

        var data = buf.toString().trim();

        if (hasError)
            return errback(data);

        try {
            callback(DResult(data));
        } catch (e:Any) {
            errback(jsonrpc.ErrorUtils.errorToString(e, "Exception while handling Haxe completion response: "));
        }
    }
}

class HaxeServer {
    var proc:ChildProcessObject;

    var buffer:MessageBuffer;
    var nextMessageLength:Int;
    var context:Context;

    var requestsHead:DisplayRequest;
    var requestsTail:DisplayRequest;
    var currentRequest:DisplayRequest;
    var socketListener:js.node.net.Server;
    var stopProgressCallback:Void->Void;

    var crashes:Int = 0;

    public var version(default,null):SemVer;

    public function new(context:Context) {
        this.context = context;
    }

    static var reTrailingNewline = ~/\r?\n$/;

    public function start(?callback:Void->Void) {
        stop();

        inline function error(s) context.sendShowMessage(Error, s);

        var env = new haxe.DynamicAccess();
        for (key in js.Node.process.env.keys())
            env[key] = js.Node.process.env[key];
        for (key in context.displayServerConfig.env.keys())
            env[key] = context.displayServerConfig.env[key];

        var haxePath = context.displayServerConfig.path;
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

        if (checkRun.status != 0)
            return error("Haxe version check failed: " + output);

        version = SemVer.parse(output);
        if (version == null)
            return error("Error parsing Haxe version " + haxe.Json.stringify(output));

        var isVersionSupported = version >= new SemVer(3, 4, 0);
        if (!isVersionSupported)
            return error('Unsupported Haxe version! Minimum version required: 3.4.0. Found: $version.');

        buffer = new MessageBuffer();
        nextMessageLength = -1;

        proc = ChildProcess.spawn(context.displayServerConfig.path, context.displayServerConfig.arguments.concat(["--wait", "stdio"]), {env: env});

        proc.stdout.on(ReadableEvent.Data, function(buf:Buffer) {
            context.sendLogMessage(Log, reTrailingNewline.replace(buf.toString(), ""));
        });
        proc.stderr.on(ReadableEvent.Data, onData);

        proc.on(ChildProcessEvent.Exit, onExit);

        if (context.config.buildCompletionCache && context.displayArguments != null) {
            stopProgressCallback = context.startProgress("Initializing Completion");
            trace("Initializing completion cache...");
            process(context.displayArguments.concat(["--no-output"]), null, null, function(_) {
                stopProgress();
                trace("Done.");
            }, function(errorMessage) {
                stopProgress();
                trace("Failed - try fixing the error(s) and restarting the language server:\n\n" + errorMessage);
            });
        }

        var displayPort = context.config.displayPort;
        if (displayPort != null) {
            if (displayPort == "auto") {
                getAvailablePort(6000).then(startSocketServer);
            } else {
                startSocketServer(displayPort);
            }
        }

        if (callback != null)
            callback();
    }

    // https://gist.github.com/mikeal/1840641#gistcomment-2337132
    function getAvailablePort(startingAt:Int):Promise<Int> {
        function getNextAvailablePort(currentPort:Int, cb:Int->Void) {
            var server = Net.createServer();
            server.listen(currentPort, () -> {
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
                function send(message:String) {
                    socket.write(message);
                    socket.end();
                    socket.destroy();
                    trace("Client disconnected");
                }
                function processDisplayResult(d:DisplayResult) {
                    send(switch (d) {
                        case DResult(r): r;
                        case DCancelled: "";
                    });
                }
                process(split, null, null, processDisplayResult, send, socket);
            });
            socket.on(SocketEvent.Error, function(err) {
                trace("Socket error: " + err);
            });
        });
        socketListener.listen(port);
        context.sendLogMessage(Log, 'Listening on port $port');
        context.protocol.sendNotification(VshaxeMethods.DidChangeDisplayPort, {port: port});
    }

    public function stop() {
        if (proc != null) {
            proc.removeAllListeners();
            proc.kill();
            proc = null;
        }

        if (socketListener != null) {
            socketListener.close();
        }

        stopProgress();

        // cancel all callbacks
        var request = requestsHead;
        while (request != null) {
            request.cancel();
            request = request.next;
        }

        requestsHead = requestsTail = currentRequest = null;
    }

    function stopProgress() {
        if (stopProgressCallback != null) {
            stopProgressCallback();
        }
        stopProgressCallback = null;
    }

    public function restart(reason:String, ?callback:Void->Void) {
        context.sendLogMessage(Log, 'Restarting Haxe completion server: $reason');
        start(callback);
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
            context.sendShowMessage(Error, 'Invalid compiler argument \'$option\' detected. '
                + 'Please verify "haxe.displayConfigurations" and "haxe.displayServer.arguments".');
            return;
        }

        context.sendShowMessage(Error, "Haxe process has crashed 3 times, not attempting any more restarts. Please check the output channel for the full error.");
        trace("\nError message from the compiler:\n");
        trace(haxeResponse);
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

    public function process(args:Array<String>, token:CancellationToken, stdin:String, callback:DisplayResult->Void, errback:String->Void, socket:Socket = null) {
        // create a request object
        var request = new DisplayRequest(token, args, stdin, callback, errback, socket);

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

    public function getContent():String {
        return buffer.toString("utf-8", 0, index);
    }
}

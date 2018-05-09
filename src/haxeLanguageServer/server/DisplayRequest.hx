package haxeLanguageServer.server;

import js.node.Buffer;
import jsonrpc.CancellationToken;

class DisplayRequest {
    public final cancellable:Bool;

    // these are used for the queue
    public var prev:DisplayRequest;
    public var next:DisplayRequest;

    var args:Array<String>;
    var token:CancellationToken;
    var stdin:String;
    var handler:ResultHandler;

    static var stdinSepBuf = new Buffer([1]);

    public function new(args:Array<String>, token:CancellationToken, cancellable:Bool, stdin:String, handler:ResultHandler) {
        this.args = args;
        this.token = token;
        this.cancellable = cancellable;
        this.stdin = stdin;
        this.handler = handler;
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
        switch (handler) {
            case Raw(callback) | Processed(callback, _):
                callback(DCancelled);
        }
    }

    public function onData(data:String) {
        if (token != null && token.canceled)
            return cancel();

        switch (handler) {
            case Raw(callback):
                callback(DResult(data));
            case Processed(callback, errback):
                processResult(data, callback, errback);
        }
    }

    function processResult(data:String, callback:DisplayResult->Void, errback:(error:String)->Void) {
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
            return errback(data);

        try {
            callback(DResult(data));
        } catch (e:Any) {
            errback(jsonrpc.ErrorUtils.errorToString(e, "Exception while handling Haxe completion response: "));
        }
    }
}

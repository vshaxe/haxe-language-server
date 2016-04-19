import js.node.child_process.ChildProcess as ChildProcessObject;
import js.node.Buffer;
import js.node.ChildProcess;
import js.node.Net;
import js.node.net.Socket;
import js.node.stream.Readable;
import jsonrpc.Protocol.RequestToken;
using StringTools;

class HaxeServer {
    var proc:ChildProcessObject;
    var port:Int;

    public function new() {
    }

    public function start(port:Int) {
        this.port = port;
        stop();
        proc = ChildProcess.spawn("haxe", ["--wait", "" + port], {stdio: Ignore});
    }

    public function stop() {
        if (proc != null) {
            proc.kill();
            proc = null;
        }
    }

    public function process(args:Array<String>, token:RequestToken, stdin:String, cb:String->Void) {
        if (stdin != null) {
            args.push("-D");
            args.push("display-stdin");
        }
        var socket = Net.connect(port);
        socket.on(SocketEvent.Connect, function() {
            if (token.canceled) {
                socket.end();
                return cb(null);
            }

            for (arg in args)
                socket.write(arg + "\n");
            if (stdin != null) {
                socket.write("\x01");
                socket.write(stdin);
            }
            socket.write("\x00");

            var chunks = [];
            var totalLen = 0;
            socket.on(ReadableEvent.Data, function(buf:Buffer) {
                if (token.canceled) {
                    socket.end();
                    return cb(null);
                }
                chunks.push(buf);
                totalLen += buf.length;
            });
            socket.on(SocketEvent.End, function() {
                if (token.canceled)
                    return cb(null);
                if (totalLen == 0)
                    return cb(""); // no data received - can happen
                var data = Buffer.concat(chunks, totalLen);
                var buf = new StringBuf();
                for (line in data.toString().split("\n")) {
                    switch (line.fastCodeAt(0)) {
                        case 0x01: // print
                        case 0x02: // error
                        default:
                            buf.add(line);
                            buf.addChar("\n".code);
                    }
                }

                try {
                    cb(buf.toString());
                } catch (e:Dynamic) {
                    token.error(ErrorUtils.errorToString(e, "Exception while handling haxe completion response: "));
                }
            });
        });
    }
}

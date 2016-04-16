import js.node.child_process.ChildProcess as ChildProcessObject;
import js.node.Buffer;
import js.node.ChildProcess;
import js.node.Net;
import js.node.net.Socket;
import js.node.stream.Readable;
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

    public function process(args:Array<String>, cancelToken:jsonrpc.Protocol.CancelToken, stdin:String, cb:String->Void) {
        if (stdin != null) {
            args.push("-D");
            args.push("display-stdin");
        }
        var socket = Net.connect(port);
        socket.on(SocketEvent.Connect, function() {
            if (cancelToken.canceled) {
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

            var data:Buffer = null;
            socket.on(ReadableEvent.Data, function(buf) {
                socket.end();
                if (cancelToken.canceled)
                    return cb(null);
                data = buf;
            });
            socket.on(SocketEvent.End, function() {
                if (cancelToken.canceled)
                    return cb(null);
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
                cb(buf.toString());
            });
        });
    }
}

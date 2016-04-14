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

    public function process(args:Array<String>, cb:String->Void) {
        var socket = Net.connect(port);
        socket.on(SocketEvent.Connect, function() {
            for (arg in args)
                socket.write(arg + "\n");
            socket.write(zero);
        });
        var data = new StringBuf();
        socket.on(ReadableEvent.Data, function(buf) {
            data.add((buf : Buffer).toString());
            socket.end();
        });
        socket.on(SocketEvent.End, function() {
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
    }
    static var zero = String.fromCharCode(0);
}

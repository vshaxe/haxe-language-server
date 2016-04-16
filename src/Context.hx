import jsonrpc.Protocol.CancelToken;

class Context {
    public var workspacePath:String;
    public var hxmlFile:String;
    var haxeServer:HaxeServer;
    var documents:TextDocuments;
    public var protocol(default,null):vscode.Protocol;

    static inline var HAXE_SERVER_PORT = 6000;

    public function new(protocol) {
        this.protocol = protocol;
        haxeServer = new HaxeServer();
        haxeServer.start(HAXE_SERVER_PORT);
        documents = new TextDocuments();
        documents.listen(protocol);
    }

    public function setConfig(config:Config) {
        hxmlFile = config.buildFile;
    }

    public inline function getDocument(uri:String):TextDocument {
        return documents.get(uri);
    }

    public function callDisplay(args:Array<String>, stdin:String, cancelToken:CancelToken, callback:String->Void) {
        var args = [
            "--cwd", workspacePath, // change cwd to workspace root
            hxmlFile, // call completion file
            "-D", "display-details",
            "--no-output", // prevent generation
        ].concat(args);
        haxeServer.process(args, cancelToken, stdin, callback);
    }

    public function shutdown() {
        haxeServer.stop();
    }
}

typedef Config = {
    var buildFile:String;
}
package features;

import jsonrpc.Protocol.RequestToken;

class Feature {
    var context:Context;

    public function new(context) {
        this.context = context;
        init();
    }

    function init() {}

    function callDisplay(args:Array<String>, stdin:String, token:RequestToken, callback:String->Void) {
        var args = [
            "--cwd", context.workspacePath, // change cwd to workspace root
            context.hxmlFile, // call completion file
            "-D", "display-details",
            "--no-output", // prevent generation
        ].concat(args);
        context.haxeServer.process(args, token, stdin, callback);
    }
}

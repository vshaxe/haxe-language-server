package features;

import jsonrpc.Protocol.CancelToken;

class Feature {
    var context:Context;

    public function new(context) {
        this.context = context;
        init();
    }

    function init() {}

    function callDisplay(args:Array<String>, stdin:String, cancelToken:CancelToken, callback:String->Void) {
        var args = [
            "--cwd", context.workspacePath, // change cwd to workspace root
            context.hxmlFile, // call completion file
            "-D", "display-details",
            "--no-output", // prevent generation
        ].concat(args);
        context.haxeServer.process(args, cancelToken, stdin, callback);
    }
}

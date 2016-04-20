package features;

import jsonrpc.Protocol.RequestToken;

class Feature {
    var context:Context;
    var showHaxeErrorMessages:Bool;

    public function new(context) {
        this.context = context;
        showHaxeErrorMessages = true;
        init();
    }

    function init() {}

    function callDisplay(args:Array<String>, stdin:String, token:RequestToken, callback:String->Void) {
        var actualArgs = ["--cwd", context.workspacePath]; // change cwd to workspace root
        actualArgs = actualArgs.concat(context.displayArguments); // add arguments from the workspace settings
        actualArgs = actualArgs.concat([
            "-D", "display-details", // get more details in completion results,
            "--no-output", // prevent anygeneration
        ]);
        actualArgs = actualArgs.concat(args); // finally, add given query args
        context.haxeServer.process(actualArgs, token, stdin, callback, function(error) {
            var report = showHaxeErrorMessages && (error != NO_COMPLETION_MESSAGE); // don't spam with these
            token.error("Got error from haxe server (see dev console): " + error, report);
        });
    }

    static var NO_COMPLETION_MESSAGE = "Error: No completion point was found";
}

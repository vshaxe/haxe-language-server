package haxeLanguageServer.features;

import jsonrpc.CancellationToken;

class Feature {
    var context:Context;

    public function new(context) {
        this.context = context;
        init();
    }

    function init() {}

    function callDisplay(args:Array<String>, stdin:String, token:CancellationToken, callback:String->Void, errback:String->Void) {
        var actualArgs = ["--cwd", context.workspacePath]; // change cwd to workspace root
        actualArgs = actualArgs.concat(context.displayArguments); // add arguments from the workspace settings
        actualArgs = actualArgs.concat([
            "-D", "display-details", // get more details in completion results,
            "--no-output", // prevent anygeneration
        ]);
        actualArgs = actualArgs.concat(args); // finally, add given query args
        context.haxeServer.process(actualArgs, token, stdin, callback, function(error) errback("Error from haxe server: " + error));
    }
}

package haxeLanguageServer.features;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

class DeterminePackageFeature {
    var context:Context;

    public function new(context) {
        this.context = context;
        context.protocol.onRequest(HaxeMethods.DeterminePackage, onDeterminePackage);
    }

    function onDeterminePackage(params:{fsPath:String}, token:CancellationToken, resolve:{pack:String}->Void, reject:ResponseError<NoData>->Void) {
        var args = ["--display", '${params.fsPath}@0@package'];
        context.callDisplay(args, null, token, function(r) {
            switch (r) {
                case DCancelled:
                    return resolve(null);
                case DResult(data):
                    resolve({pack: data});
            }
        }, function(error) reject(ResponseError.internalError(error)));
    }
}

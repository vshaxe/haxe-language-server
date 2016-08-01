package haxeLanguageServer.features;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

class CalculatePackageFeature {
    var context:Context;

    public function new(context) {
        this.context = context;
        context.protocol.onVSHaxeCalculatePackage = onCalculatePackage;
    }

    function onCalculatePackage(params:{fsPath:String}, token:CancellationToken, resolve:{pack:String}->Void, reject:ResponseError<NoData>->Void) {
        var args = ["--display", '${params.fsPath}@0@package'];
        context.callDisplay(args, null, token, function(data) {
            if (token.canceled)
                return;
            resolve({pack: data});
        }, function(error) reject(ResponseError.internalError(error)));
    }
}

package haxeLanguageServer.features;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import haxeLanguageServer.server.Protocol;

class DeterminePackageFeature {
    final context:Context;

    public function new(context) {
        this.context = context;
        context.protocol.onRequest(LanguageServerMethods.DeterminePackage, onDeterminePackage);
    }

    function onDeterminePackage(params:{fsPath:String}, token:CancellationToken, resolve:{pack:String}->Void, reject:ResponseError<NoData>->Void) {
        var handle = if (context.haxeServer.capabilities.packageProvider) handleJsonRpc else handleLegacy;
        handle(params, token, resolve, reject);
    }

    function handleJsonRpc(params:{fsPath:String}, token:CancellationToken, resolve:{pack:String}->Void, reject:ResponseError<NoData>->Void) {
        context.callHaxeMethod(HaxeMethods.DeterminePackage, {file: new FsPath(params.fsPath)}, token,
            result -> resolve({pack: result.join(".")}),
            error -> reject(ResponseError.internalError(error))
        );
    }

    function handleLegacy(params:{fsPath:String}, token:CancellationToken, resolve:{pack:String}->Void, reject:ResponseError<NoData>->Void) {
        var args = ['${params.fsPath}@0@package'];
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

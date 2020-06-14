package haxeLanguageServer.features.haxe;

import haxe.display.Display;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

class DeterminePackageFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.languageServerProtocol.onRequest(LanguageServerMethods.DeterminePackage, onDeterminePackage);
	}

	public function onDeterminePackage(params:{fsPath:String}, token:CancellationToken, resolve:{pack:String}->Void, reject:ResponseError<NoData>->Void) {
		var handle = if (context.haxeServer.supports(DisplayMethods.DeterminePackage)) handleJsonRpc else handleLegacy;
		handle(new FsPath(params.fsPath), token, resolve, reject);
	}

	function handleJsonRpc(path:FsPath, token:CancellationToken, resolve:{pack:String}->Void, reject:ResponseError<NoData>->Void) {
		context.callHaxeMethod(DisplayMethods.DeterminePackage, {file: path}, token, result -> {
			resolve({pack: result.join(".")});
			return null;
		}, reject.handler());
	}

	function handleLegacy(path:FsPath, token:CancellationToken, resolve:{pack:String}->Void, reject:ResponseError<NoData>->Void) {
		var args = ['$path@0@package'];
		context.callDisplay("@package", args, null, token, function(r) {
			switch r {
				case DCancelled:
					return resolve(null);
				case DResult(data):
					resolve({pack: data});
			}
		}, reject.handler());
	}
}

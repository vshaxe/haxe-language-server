package haxeLanguageServer.helper;

import jsonrpc.Types.NoData;
import jsonrpc.ResponseError;

class ResponseErrorHelper {
	public static function handler(reject:ResponseError<NoData>->Void) {
		return function(error:String) reject(ResponseError.internalError(error));
	}

	public static function invalidXml(reject:ResponseError<NoData>->Void, data:String) {
		reject(ResponseError.internalError("Invalid xml data: " + data));
	}

	public static function notAFile(reject:ResponseError<NoData>->Void) {
		reject(ResponseError.internalError("Only supported for file:// URIs"));
	}

	public static function noTokens(reject:ResponseError<NoData>->Void) {
		reject(ResponseError.internalError("Unable to build token tree"));
	}
}

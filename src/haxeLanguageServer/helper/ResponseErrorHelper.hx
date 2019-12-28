package haxeLanguageServer.helper;

import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

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

	public static function documentNotFound(reject:ResponseError<NoData>->Void, uri:DocumentUri) {
		reject(ResponseError.internalError("Unable to find document for URI " + uri));
	}
}

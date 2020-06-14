package haxeLanguageServer.helper;

import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

function handler(reject:ResponseError<NoData>->Void) {
	return function(error:String) reject(ResponseError.internalError(error));
}

function invalidXml(reject:ResponseError<NoData>->Void, data:String) {
	reject(ResponseError.internalError("Invalid xml data: " + data));
}

function noTokens(reject:ResponseError<NoData>->Void) {
	reject(ResponseError.internalError("Unable to build token tree"));
}

function noFittingDocument(reject:ResponseError<NoData>->Void, uri:DocumentUri) {
	reject(ResponseError.internalError('Unable to find document for URI $uri, or feature is not supported for this file type / scheme'));
}

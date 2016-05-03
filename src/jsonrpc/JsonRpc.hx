package jsonrpc;

import jsonrpc.Types;

/**
    This class provides helper methods for creating JSON-RPC messages.
**/
class JsonRpc {
    /**
        Create `ResponseError` for given `code`, `message` and `data`.
    **/
    public static function error<T>(code:Int, message:String, ?data:T):ResponseError<T> {
        var error:ResponseError<T> = {
            code: code,
            message: message,
        };
        if (data != null)
            error.data = data;
        return error;
    }
}

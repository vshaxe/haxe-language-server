/*
    This module contains basic JSON-RPC types and helper methods.
*/

/**
    A general message as defined by JSON-RPC.
**/
typedef Message = {
    /**
        JSON-RPC version.
        The language server protocol always uses "2.0".
    **/
    var jsonrpc:String;
}

typedef RequestId = haxe.extern.EitherType<Int,String>;

/**
    A request message to decribe a request between the client and the server.
    Every processed request must send a response back to the sender of the request.
**/
typedef RequestMessage = {
    >Message,

    /**
        The request id.
    **/
    var id:RequestId;

    /**
        The method to be invoked.
    **/
    var method:String;

    /**
        The method's params.
    **/
    @:optional var params:Dynamic;
}

/**
    Response Message send as a result of a request.
**/
typedef ResponseMessage = {
    >Message,

    /**
        The request id.
    **/
    var id:RequestId;

    /**
        The result of a request. This can be omitted in the case of an error.
    **/
    @:optional var result:Dynamic;

    /**
        The error object in case a request fails.
    **/
    @:optional var error:ResponseError<Dynamic>;
}

/**
    Error object sent in the `ResponseMessage.error` field.
**/
typedef ResponseError<D> = {
    /**
        A number indicating the error type that occured.
    **/
    var code:Int;

    /**
        A string providing a short decription of the error.
    **/
    var message:String;

    /**
        A Primitive or Structured value that contains additional information about the error.
    **/
    @:optional var data:D;
}

/**
    Reserved error codes.
**/
@:publicFields
class ErrorCodes {
    /**
        Invalid JSON was received by the server.
        An error occurred on the server while parsing the JSON text.
    **/
    static inline var ParseError = -32700;

    /**
        The JSON sent is not a valid Request object.
    **/
    static inline var InvalidRequest = -32600;

    /**
        The method does not exist / is not available.
    **/
    static inline var MethodNotFound = -32601;

    /**
        Invalid method parameter(s).
    **/
    static inline var InvalidParams = -32602;

    /**
        Internal JSON-RPC error.
    **/
    static inline var InternalError = -32603;
}

/**
    A notification message. A processed notification message must not send a response back.
    They work like events.
**/
typedef NotificationMessage = {
    >Message,

    /**
        The method to be invoked.
    **/
    var method:String;

    /**
        The notification's params.
    **/
    @:optional var params:Dynamic;
}

/**
    Parameters for request cancellation notification.
**/
private typedef CancelParams = {
    /**
        The request id to cancel.
    **/
    var id:RequestId;
}

class JsonRpc {
    static inline var PROTOCOL_VERSION = "2.0";
    static inline var CANCEL_METHOD = "$/cancelRequest";

    /**
        Create `NotificationMessage` for given `method` and `params`.
    **/
    public static function notification<D>(method:String, ?params:D):NotificationMessage {
        var message:NotificationMessage = {
            jsonrpc: PROTOCOL_VERSION,
            method: method
        };
        if (params == null)
            message.params = params;
        return message;
    }

    /**
        Create `RequestMessage` for given `id`, `method` and `params`.
    **/
    public static function request<D>(id:RequestId, method:String, ?params:D):RequestMessage {
        var message:RequestMessage = {
            jsonrpc: PROTOCOL_VERSION,
            id: id,
            method: method
        };
        if (params == null)
            message.params = params;
        return message;
    }

    /**
        Create cancellation notification for given request `id`.
    **/
    public static inline function cancel(id:RequestId):NotificationMessage {
        return notification(CANCEL_METHOD, ({id: id} : CancelParams));
    }

    /**
        Create `ResponseMessage` for given request `id`.
        If `outcome` is `Left` - the error response will be generated for given error data.
        If `outcome` is `Right` - the result response will be generated for given result data.
    **/
    public static function response<D,E>(id:RequestId, outcome:haxe.ds.Either<ResponseError<E>,D>):ResponseMessage {
        var response:ResponseMessage = {
            jsonrpc: PROTOCOL_VERSION,
            id: id,
        };
        switch (outcome) {
            case Left(var error):
                response.error = error;
            case Right(var result):
                response.result = result;
        }
        return response;
    }

    /**
        Create `ResponseError`  for given `code`, `message` and `data`.
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

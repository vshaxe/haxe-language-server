import haxe.extern.EitherType;

typedef Message = {
    var jsonrpc:String;
}

typedef RequestId = EitherType<Int,String>;

typedef RequestMessage = {
    >Message,
    var id:RequestId;
    var method:String;
    @:optional var params:Dynamic;
}

typedef ResponseMessage = {
    >Message,
    var id:RequestId;
    @:optional var result:Dynamic;
    @:optional var error:ResponseError<Dynamic>;
}

typedef ResponseError<D> = {
    var code:Int;
    var message:String;
    @:optional var data:D;
}

@:publicFields
class ErrorCodes {
    static inline var ParseError = -32700;
    static inline var InvalidRequest = -32600;
    static inline var MethodNotFound = -32601;
    static inline var InvalidParams = -32602;
    static inline var InternalError = -32603;
    static inline var serverErrorStart = -32099;
    static inline var serverErrorEnd = -32000;
}

typedef NotificationMessage = {
    >Message,
    var method:String;
    @:optional var params:Dynamic;
}

typedef CancelParams = {
    var id:RequestId;
}

typedef CancelCallback = Void -> Void;

class JsonRpc {
    public static inline var PROTOCOL_VERSION = "2.0";

    public static inline function cancel(id:RequestId):NotificationMessage {
        return {
            jsonrpc: PROTOCOL_VERSION,
            method: "$/cancelRequest",
            params: ({id: id} : CancelParams)
        };
    }
}

package jsonrpc;

import jsonrpc.Types;

/**
    A simple JSON-RPC protocol base class.
**/
class Protocol {
    var writeMessage:Message->Void;
    var cancelTokens:Map<String,CancelToken>;

    public function new(writeMessage) {
        this.writeMessage = writeMessage;
        cancelTokens = new Map();
    }

    public function handleMessage(message:Message):Void {
        if (!Reflect.hasField(message, "method"))
            return;
        if (Reflect.hasField(message, "id")) {
            var request:RequestMessage = cast message;
            var tokenKey = Std.string(request.id);
            var token = cancelTokens[tokenKey] = {canceled: false};
            function resolve(result:Dynamic) {
                cancelTokens.remove(tokenKey);
                sendResponse(JsonRpc.response(request.id, result, null));
            }
            function reject<T>(error:ResponseError<T>) {
                cancelTokens.remove(tokenKey);
                sendResponse(JsonRpc.response(request.id, null, error));
            }
            try {
                handleRequest(request, token, resolve, reject);
            } catch (e:Dynamic) {
                cancelTokens.remove(tokenKey);
                reject(JsonRpc.error(jsonrpc.ErrorCodes.InternalError, 'Request ${request.method} failed with error: ${Std.string(e)}'));
            }
        } else {
            var notification:NotificationMessage = cast message;
            if (notification.method == jsonrpc.JsonRpc.CANCEL_METHOD)
                cancelRequest(notification.params);
            else
                handleNotification(notification);
        }
    }

    function cancelRequest(params:jsonrpc.Types.CancelParams) {
        var tokenKey = Std.string(params.id);
        var token = cancelTokens[tokenKey];
        if (token != null) {
            token.canceled = true;
            cancelTokens.remove(tokenKey);
        }
    }

    inline function sendResponse(response:ResponseMessage):Void {
        writeMessage(response);
    }

    inline function sendNotification(name:String, params:Dynamic):Void {
        writeMessage(JsonRpc.notification(name, params));
    }

    // these should be implemented in sub-class
    function handleRequest(request:RequestMessage, cancelToken:CancelToken, resolve:ResolveHandler, reject:RejectHandler):Void {
        reject(JsonRpc.error(ErrorCodes.InternalError, "handleRequest not implemented"));
    }

    function handleNotification(notification:NotificationMessage):Void {
    }
}

typedef ResolveHandler = Dynamic->Void
typedef RejectHandler = ResponseError<Void>->Void
typedef RejectDataHandler<T> = ResponseError<T>->Void

typedef CancelToken = {
    var canceled:Bool;
}

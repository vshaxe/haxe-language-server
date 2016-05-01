package jsonrpc;

import jsonrpc.Types;
import ErrorUtils.errorToString;

/**
    A simple JSON-RPC protocol base class.
**/
class Protocol {
    var writeMessage:Message->Void;
    var requestTokens:Map<String,RequestToken>;

    public function new(writeMessage) {
        this.writeMessage = writeMessage;
        requestTokens = new Map();
    }

    public function handleMessage(message:Message):Void {
        if (!Reflect.hasField(message, "method"))
            return;
        if (Reflect.hasField(message, "id")) {
            var request:RequestMessage = cast message;
            var tokenKey = Std.string(request.id);
            function resolve(result:Dynamic) {
                requestTokens.remove(tokenKey);
                sendResponse(JsonRpc.response(request.id, result, null));
            }
            function reject<T>(error:ResponseError<T>) {
                requestTokens.remove(tokenKey);
                sendResponse(JsonRpc.response(request.id, null, error));
            }
            var token = requestTokens[tokenKey] = new RequestToken();
            try {
                handleRequest(request, token, resolve, reject);
            } catch (e:Dynamic) {
                requestTokens.remove(tokenKey);
                var message = errorToString(e, 'Exception while handling request ${request.method}: ');
                reject(jsonrpc.JsonRpc.error(jsonrpc.ErrorCodes.InternalError, message));
                logError(message);
            }
        } else {
            var notification:NotificationMessage = cast message;
            if (notification.method == jsonrpc.JsonRpc.CANCEL_METHOD)
                cancelRequest(notification.params);
            else {
                try {
                    handleNotification(notification);
                } catch (e:Dynamic) {
                    logError(errorToString(e, 'Exception while handing notification ${notification.method}: '));
                }
            }
        }
    }

    function cancelRequest(params:jsonrpc.Types.CancelParams) {
        var tokenKey = Std.string(params.id);
        var token = requestTokens[tokenKey];
        if (token != null) {
            token.canceled = true;
            requestTokens.remove(tokenKey);
        }
    }

    inline function sendResponse(response:ResponseMessage):Void {
        writeMessage(response);
    }

    inline function sendNotification(name:String, params:Dynamic):Void {
        writeMessage(JsonRpc.notification(name, params));
    }

    // these should be implemented in sub-class
    function handleRequest(request:RequestMessage, cancelToken:RequestToken, resolve:ResolveHandler, reject:RejectHandler):Void {
        reject(JsonRpc.error(ErrorCodes.InternalError, "handleRequest not implemented"));
    }

    function handleNotification(notification:NotificationMessage):Void {
    }

    function logError(message:String):Void {
    }
}

typedef ResolveHandler = Dynamic->Void
typedef RejectHandler = ResponseError<Void>->Void
typedef RejectDataHandler<T> = ResponseError<T>->Void

class RequestToken {
    @:allow(jsonrpc.Protocol.cancelRequest)
    public var canceled(default,null):Bool;

    public function new() {
        canceled = false;
    }
}

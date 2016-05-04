package jsonrpc;

import jsonrpc.Types;
import ErrorUtils.errorToString;

/**
    A simple JSON-RPC protocol base class.
**/
class Protocol {
    static inline var PROTOCOL_VERSION = "2.0";
    static inline var CANCEL_METHOD = "$/cancelRequest";

    var writeMessage:Message->Void;
    var requestTokens:Map<String,CancellationToken>;

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
                sendResponse({
                    jsonrpc: PROTOCOL_VERSION,
                    id: request.id,
                    result: result
                });
            }
            function reject<T>(error:ResponseError<T>) {
                requestTokens.remove(tokenKey);
                sendResponse({
                    jsonrpc: PROTOCOL_VERSION,
                    id: request.id,
                    error: error
                });
            }
            var token = requestTokens[tokenKey] = new CancellationToken();
            try {
                handleRequest(request, token, resolve, reject);
            } catch (e:Dynamic) {
                requestTokens.remove(tokenKey);
                var message = errorToString(e, 'Exception while handling request ${request.method}: ');
                reject(new ResponseError(jsonrpc.ErrorCodes.InternalError, message));
                logError(message);
            }
        } else {
            var notification:NotificationMessage = cast message;
            if (notification.method == CANCEL_METHOD)
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

    function cancelRequest(params:CancelParams) {
        var tokenKey = Std.string(params.id);
        var token = requestTokens[tokenKey];
        if (token != null) {
            token.cancel();
            requestTokens.remove(tokenKey);
        }
    }

    inline function sendResponse(response:ResponseMessage):Void {
        writeMessage(response);
    }

    inline function sendNotification(name:String, params:Dynamic):Void {
        var message:NotificationMessage = {
            jsonrpc: PROTOCOL_VERSION,
            method: name
        };
        if (params != null)
            message.params = params;
        writeMessage(message);
    }

    // these should be implemented in sub-class
    function handleRequest(request:RequestMessage, cancelToken:CancellationToken, resolve:Dynamic->Void, reject:ResponseError<Dynamic>->Void):Void {
        reject(new ResponseError(ErrorCodes.InternalError, 'Unhandled method ${request.method}'));
    }

    function handleNotification(notification:NotificationMessage):Void {
    }

    function logError(message:String):Void {
    }
}

class CancellationToken {
    public var canceled(default,null):Bool;

    public function new() {
        canceled = false;
    }

    @:allow(jsonrpc.Protocol.cancelRequest)
    inline function cancel() {
        canceled = true;
    }
}

/**
    Parameters for request cancellation notification.
**/
typedef CancelParams = {
    /**
        The request id to cancel.
    **/
    var id:RequestId;
}

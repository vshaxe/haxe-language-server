package jsonrpc;

import jsonrpc.Types;
import jsonrpc.ErrorUtils.errorToString;

/**
    A simple JSON-RPC protocol base class.
**/
class Protocol {
    static inline var PROTOCOL_VERSION = "2.0";
    static inline var CANCEL_METHOD = new NotificationMethod<CancelParams>("$/cancelRequest");

    var writeMessage:Message->Void;
    var requestTokens:Map<String,CancellationTokenSource>;
    var nextRequestId:Int;
    var responseCallbacks:Map<Int,ResponseCallbackEntry>;

    public function new(writeMessage) {
        this.writeMessage = writeMessage;
        requestTokens = new Map();
        nextRequestId = 0;
    }

    public function handleMessage(message:Message):Void {
        if ((Reflect.hasField(message, "result") || Reflect.hasField(message, "error")) && Reflect.hasField(message, "id")) {
            handleResponse(cast message);
        } else if (Reflect.hasField(message, "method")) {
            if (Reflect.hasField(message, "id"))
                handleRequest(cast message);
            else
                handleNotification(cast message);
        }
    }

    function handleRequest(request:RequestMessage) {
        var tokenKey = Std.string(request.id);

        function resolve(result:Dynamic) {
            requestTokens.remove(tokenKey);

            var response:ResponseMessage = {
                jsonrpc: PROTOCOL_VERSION,
                id: request.id,
                result: result
            };
            writeMessage(response);
        }

        function reject(error:ResponseErrorData) {
            requestTokens.remove(tokenKey);

            var response:ResponseMessage = {
                jsonrpc: PROTOCOL_VERSION,
                id: request.id,
                error: error
            };
            writeMessage(response);
        }

        var tokenSource = new CancellationTokenSource();
        requestTokens[tokenKey] = tokenSource;

        try {
            processRequest(request, tokenSource.token, resolve, reject);
        } catch (e:Dynamic) {
            requestTokens.remove(tokenKey);

            var message = errorToString(e, 'Exception while handling request ${request.method}: ');
            reject(new ResponseError(jsonrpc.ErrorCodes.InternalError, message));
            logError(message);
        }
    }

    function handleNotification(notification:NotificationMessage) {
        if (notification.method == CANCEL_METHOD) {
            var tokenKey = Std.string(notification.params.id);
            var tokenSource = requestTokens[tokenKey];
            if (tokenSource != null) {
                requestTokens.remove(tokenKey);
                tokenSource.cancel();
            }
        } else {
            try {
                processNotification(notification);
            } catch (e:Dynamic) {
                logError(errorToString(e, 'Exception while processing notification ${notification.method}: '));
            }
        }
    }

    function handleResponse(response:ResponseMessage) {
        if (!(response.id is Int)) {
            logError("Got response with non-integer id:\n" + haxe.Json.stringify(response, "    "));
            return;
        }
        var handler = responseCallbacks[response.id];
        if (handler != null) {
            responseCallbacks.remove(response.id);
            try {
                if (Reflect.hasField(response, "error"))
                    handler.reject(response.error);
                else
                    handler.resolve(response.result);
            } catch (e:Dynamic) {
                logError(errorToString(e, 'Exception while handing response ${handler.method}: '));
            }
        }
    }

    inline function sendNotification<P>(name:NotificationMethod<P>, params:P):Void {
        var message:NotificationMessage = {
            jsonrpc: PROTOCOL_VERSION,
            method: name
        };
        if (params != null)
            message.params = params;
        writeMessage(message);
    }

    function sendRequest<P,R,E>(method:RequestMethod<P,R,E>, params:P, token:Null<CancellationToken>, resolve:P->Void, reject:E->Void):Void {
        var id = nextRequestId++;
        var request:RequestMessage = {
            jsonrpc: PROTOCOL_VERSION,
            id: id,
            method: method,
        };
        if (params != null)
            request.params = params;
        responseCallbacks[id] = new ResponseCallbackEntry(method, resolve, reject);
        if (token != null)
            token.setCallback(function() sendNotification(CANCEL_METHOD, {id: id}));
        writeMessage(request);
    }

    // these should be implemented in sub-class
    function processRequest(request:RequestMessage, cancelToken:CancellationToken, resolve:Dynamic->Void, reject:ResponseError<Dynamic>->Void):Void {
        reject(new ResponseError(ErrorCodes.MethodNotFound, 'Unhandled method ${request.method}'));
    }

    function processNotification(notification:NotificationMessage):Void {
    }

    function logError(message:String):Void {
    }
}

abstract CancellationToken(CancellationTokenImpl) {
    public var canceled(get,never):Bool;
    inline function get_canceled() return this.canceled;
    public inline function setCallback(cb:Void->Void) this.callback = cb;
}

abstract CancellationTokenSource(CancellationTokenImpl) {
    public var token(get,never):CancellationToken;
    inline function get_token():CancellationToken return cast this;
    public inline function new() this = new CancellationTokenImpl();
    public inline function cancel() this.cancel();
}

private class CancellationTokenImpl {
    public var canceled(default,null):Bool;
    public var callback:Void->Void;

    public inline function new() {
        canceled = false;
    }

    public inline function cancel() {
        if (canceled)
            return;
        canceled = true;
        if (callback != null)
            callback();
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


private class ResponseCallbackEntry {
    public var method:String;
    public var resolve:Dynamic->Void;
    public var reject:Dynamic->Void;
    public function new(method, resolve, reject) {
        this.method = method;
        this.resolve = resolve;
        this.reject = reject;
    }
}

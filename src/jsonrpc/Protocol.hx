package jsonrpc;

import jsonrpc.Types;

/**
    A simple JSON-RPC protocol base class.
**/
class Protocol {
    var writeMessage:Message->Void;

    public function new(writeMessage) {
        this.writeMessage = writeMessage;
    }

    public function handleMessage(message:Message):Void {
        if (!Reflect.hasField(message, "method"))
            return;
        if (Reflect.hasField(message, "id")) {
            var request:RequestMessage = cast message;
            function resolve(result) sendResponse(JsonRpc.response(request.id, Right(result)));
            function reject(code, message, data) sendResponse(JsonRpc.response(request.id, Left(JsonRpc.error(code, message, data))));
            handleRequest(request, resolve, reject);
        } else {
            handleNotification(cast message);
        }
    }

    inline function sendResponse(response:ResponseMessage):Void {
        writeMessage(response);
    }

    inline function sendNotification(name:String, params:Dynamic):Void {
        writeMessage(JsonRpc.notification(name, params));
    }

    // these should be implemented in sub-class
    function handleRequest(request:RequestMessage, resolve:Dynamic->Void, reject:Int->String->Dynamic->Void):Void {
        reject(ErrorCodes.InternalError, "handleRequest not implemented", null);
    }

    function handleNotification(notification:NotificationMessage):Void {
    }
}

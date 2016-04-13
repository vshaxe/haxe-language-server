import haxe.extern.EitherType;
import JsonRpc;
import BasicTypes;
import ProtocolTypes;

@:build(ProtocolMacro.build())
class Protocol {
    public function new() {}
    public function handleMessage(message:Message):Void {
        trace("Handling message: " + message);
        if (Reflect.hasField(message, "id")) {
            var request:RequestMessage = cast message;
            function resolve(result) sendResponse(JsonRpc.response(request.id, Right(result)));
            function reject(code, message, data) sendResponse(JsonRpc.response(request.id, Left(JsonRpc.error(code, message, data))));
            handleRequest(request, resolve, reject);
        } else {
            handleNotification(cast message);
        }
    }

    public inline function sendResponse(response:ResponseMessage):Void sendMessage(response);
    public inline function sendNotification(name:String, params:Dynamic):Void sendMessage(JsonRpc.notification(name, params));
    public dynamic function sendMessage(message:Message):Void {}

    function handleRequest(request:RequestMessage, resolve:Dynamic->Void, reject:Int->String->Dynamic->Void):Void;
    function handleNotification(notification:NotificationMessage):Void;
}

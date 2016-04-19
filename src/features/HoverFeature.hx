package features;

import vscode.BasicTypes;
import vscode.ProtocolTypes;
import jsonrpc.Protocol;
import jsonrpc.ErrorCodes.internalError;

import Uri.uriToFsPath;
import SignatureHelper.*;

class HoverFeature extends Feature {
    override function init() {
        context.protocol.onHover = onHover;
    }

    function onHover(params:TextDocumentPositionParams, token:RequestToken, resolve:Hover->Void, reject:RejectHandler) {
        var doc = context.getDocument(params.textDocument.uri);
        var filePath = uriToFsPath(params.textDocument.uri);
        var bytePos = doc.byteOffsetAt(params.position);
        var args = ["--display", '$filePath@$bytePos@type'];
        var stdin = if (doc.saved) null else doc.content;
        callDisplay(args, stdin, token, function(data) {
            if (token.canceled)
                return;

            var xml = try Xml.parse(data).firstElement() catch (_:Dynamic) null;
            if (xml == null) return reject(internalError("Invalid xml data: " + data));

            var s = StringTools.trim(xml.firstChild().nodeValue);
            var type = switch (parseDisplayType(s)) {
                case DTFunction(args, ret):
                    "function" + printFunctionSignature(args, ret);
                case DTValue(type):
                    type;
            };
            resolve({contents: {language: "haxe", value: type}});
        });
    }
}

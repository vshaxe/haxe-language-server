package features;

import vscode.BasicTypes;
import vscode.ProtocolTypes;
import jsonrpc.Protocol;
import jsonrpc.ErrorCodes.internalError;

import Uri.uriToFsPath;
import SignatureHelper.prepareSignature;

class HoverFeature extends Feature {
    override function init() {
        context.protocol.onHover = onHover;
    }

    function onHover(params:TextDocumentPositionParams, cancelToken:CancelToken, resolve:Hover->Void, reject:RejectHandler) {
        var doc = context.getDocument(params.textDocument.uri);
        var filePath = uriToFsPath(params.textDocument.uri);
        var bytePos = doc.byteOffsetAt(params.position);
        var args = ["--display", '$filePath@$bytePos@type'];
        var stdin = if (doc.saved) null else doc.content;
        callDisplay(args, stdin, cancelToken, function(data) {
            if (cancelToken.canceled)
                return;

            var xml = try Xml.parse(data).firstElement() catch (_:Dynamic) null;
            if (xml == null) return reject(internalError("Invalid xml data: " + data));

            var type = xml.firstChild().nodeValue;
            resolve({contents: {language: "haxe", value: type}});
        });
    }
}
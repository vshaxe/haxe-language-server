package haxeLanguageServer.features;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import haxeLanguageServer.vscodeProtocol.Types;
import haxeLanguageServer.SignatureHelper.*;

class HoverFeature extends Feature {
    override function init() {
        context.protocol.onHover = onHover;
    }

    function onHover(params:TextDocumentPositionParams, token:CancellationToken, resolve:Hover->Void, reject:ResponseError<Void>->Void) {
        var doc = context.documents.get(params.textDocument.uri);
        var bytePos = doc.byteOffsetAt(params.position);
        var args = ["--display", '${doc.fsPath}@$bytePos@type'];
        var stdin = if (doc.saved) null else doc.content;
        callDisplay(args, stdin, token, function(data) {
            if (token.canceled)
                return;

            var xml = try Xml.parse(data).firstElement() catch (_:Dynamic) null;
            if (xml == null) return reject(ResponseError.internalError("Invalid xml data: " + data));

            var s = StringTools.trim(xml.firstChild().nodeValue);
            if (s.length == 0)
                return reject(new ResponseError(0, "No type information"));

            var type = switch (parseDisplayType(s)) {
                case DTFunction(args, ret):
                    "function" + printFunctionSignature(args, ret);
                case DTValue(type):
                    if (type == null) "unknown" else type;
            };

            var result:Hover = {contents: {language: "haxe", value: type}};
            var p = HaxePosition.parse(xml.get("p"), doc, null);
            if (p != null)
                result.range = p.range;

            resolve(result);
        }, function(error) reject(ResponseError.internalError(error)));
    }
}

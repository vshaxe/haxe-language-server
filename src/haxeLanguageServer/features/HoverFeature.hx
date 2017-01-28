package haxeLanguageServer.features;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.helper.TypeHelper.*;

class HoverFeature {
    var context:Context;

    public function new(context) {
        this.context = context;
        context.protocol.onRequest(Methods.Hover, onHover);
    }

    function onHover(params:TextDocumentPositionParams, token:CancellationToken, resolve:Hover->Void, reject:ResponseError<NoData>->Void) {
        var doc = context.documents.get(params.textDocument.uri);
        var bytePos = doc.byteOffsetAt(params.position);
        var args = ["--display", '${doc.fsPath}@$bytePos@type'];
        context.callDisplay(args, doc.content, token, function(data) {
            if (token.canceled)
                return;

            var xml = try Xml.parse(data).firstElement() catch (_:Any) null;
            if (xml == null) return reject(ResponseError.internalError("Invalid xml data: " + data));
            var s = StringTools.trim(xml.firstChild().nodeValue);
            switch (xml.nodeName) {
                case "metadata":
                    if (s.length == 0)
                        return reject(new ResponseError(0, "No metadata information"));
                    resolve({contents: s});
                case _:
                    if (s.length == 0)
                        return reject(new ResponseError(0, "No type information"));

                    var type = switch (parseDisplayType(s)) {
                        case DTFunction(args, ret):
                            printFunctionDeclaration(args, ret, {argumentTypeHints: true, returnTypeHint: Always});
                        case DTValue(type):
                            if (type == null) "unknown" else type;
                    };

                    var d = xml.get("d");
                    d = if (d == null) "" else DocHelper.markdownFormat(d);
                    var result:Hover = {contents: '```haxe\n${type}\n```\n${d}'};
                    var p = HaxePosition.parse(xml.get("p"), doc, null);
                    if (p != null)
                        result.range = p.range;

                    resolve(result);
            }
        }, function(error) reject(ResponseError.internalError(error)));
    }
}

package features;

import vscodeProtocol.BasicTypes;
import jsonrpc.Protocol;
import jsonrpc.Types;

class FindReferencesFeature extends Feature {
    override function init() {
        context.protocol.onFindReferences = onFindReferences;
    }

    function onFindReferences(params:TextDocumentPositionParams, token:CancellationToken, resolve:Array<Location>->Void, reject:ResponseError<Void>->Void) {
        var doc = context.documents.get(params.textDocument.uri);
        var bytePos = doc.byteOffsetAt(params.position);
        var args = ["--display", '${doc.fsPath}@$bytePos@usage'];
        var stdin = if (doc.saved) null else doc.content;
        callDisplay(args, stdin, token, function(data) {
            if (token.canceled)
                return;

            var xml = try Xml.parse(data).firstElement() catch (_:Dynamic) null;
            if (xml == null) return reject(ResponseError.internalError("Invalid xml data: " + data));

            var positions = [for (el in xml.elements()) el.firstChild().nodeValue];
            if (positions.length == 0)
                return resolve([]);

            var results = [];
            var haxePosCache = new Map();
            for (pos in positions) {
                var location = HaxePosition.parse(pos, doc, haxePosCache);
                if (location == null) {
                    trace("Got invalid position: " + pos);
                    continue;
                }
                results.push(location);
            }

            return resolve(results);
        }, function(error) reject(ResponseError.internalError(error)));
    }
}

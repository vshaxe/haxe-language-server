package features;

import haxe.extern.EitherType;
import vscodeProtocol.BasicTypes;
import jsonrpc.Protocol;
import jsonrpc.ErrorCodes.internalError;

class GotoDefinitionFeature extends Feature {
    override function init() {
        context.protocol.onGotoDefinition = onGotoDefinition;
    }

    function onGotoDefinition(params:TextDocumentPositionParams, token:CancellationToken, resolve:EitherType<Location,Array<Location>>->Void, reject:RejectHandler) {
        var doc = context.documents.get(params.textDocument.uri);
        var bytePos = doc.byteOffsetAt(params.position);
        var args = ["--display", '${doc.fsPath}@$bytePos@position'];
        var stdin = if (doc.saved) null else doc.content;
        callDisplay(args, stdin, token, function(data) {
            if (token.canceled)
                return;

            var xml = try Xml.parse(data).firstElement() catch (_:Dynamic) null;
            if (xml == null) return reject(internalError("Invalid xml data: " + data));

            var positions = [for (el in xml.elements()) el.firstChild().nodeValue];
            if (positions.length == 0)
                return resolve([]);

            var results = [];
            for (pos in positions) {
                var location = HaxePosition.parse(pos, doc, null); // no cache because this right now only returns one position
                if (location == null) {
                    trace("Got invalid position: " + pos);
                    continue;
                }
                results.push(location);
            }

            return resolve(results);
        }, function(error) reject(jsonrpc.ErrorCodes.internalError(error)));
    }
}

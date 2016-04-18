package features;

import vscode.BasicTypes;
import vscode.ProtocolTypes;
import jsonrpc.Protocol;
import jsonrpc.ErrorCodes.internalError;

import Uri.*;
import FsUtils.getProperFileNameCase;

class FindReferencesFeature extends Feature {
    override function init() {
        context.protocol.onFindReferences = onFindReferences;
    }

    function onFindReferences(params:TextDocumentPositionParams, cancelToken:CancelToken, resolve:Array<Location>->Void, reject:RejectHandler) {
        var doc = context.getDocument(params.textDocument.uri);
        var filePath = uriToFsPath(params.textDocument.uri);
        var bytePos = doc.byteOffsetAt(params.position);
        var args = ["--display", '$filePath@$bytePos@usage'];
        var stdin = if (doc.saved) null else doc.content;
        callDisplay(args, stdin, cancelToken, function(data) {
            if (cancelToken.canceled)
                return;

            var xml = try Xml.parse(data).firstElement() catch (_:Dynamic) null;
            if (xml == null) return reject(internalError("Invalid xml data: " + data));

            var positions = [for (el in xml.elements()) el.firstChild().nodeValue];
            if (positions.length == 0)
                return resolve([]);

            var results = [];
            var haxePosCache = new Map();
            for (p in positions) {
                var pos = HaxePosition.parse(p);
                if (pos == null) {
                    trace("Got invalid position: " + p);
                    continue;
                }
                results.push({
                    uri: fsPathToUri(getProperFileNameCase(pos.file)),
                    range: pos.toRange(haxePosCache),
                });
            }

            return resolve(results);
        });
    }
}

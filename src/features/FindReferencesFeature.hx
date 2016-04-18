package features;

import vscode.BasicTypes;
import vscode.ProtocolTypes;
import jsonrpc.Protocol.CancelToken;

import Uri.*;
import FsUtils.getProperFileNameCase;

class FindReferencesFeature extends Feature {
    override function init() {
        context.protocol.onFindReferences = onFindReferences;
    }

    function onFindReferences(params:TextDocumentPositionParams, cancelToken:CancelToken, resolve:Array<Location>->Void, reject:Int->String->Void) {
        var doc = context.getDocument(params.textDocument.uri);
        var filePath = uriToFsPath(params.textDocument.uri);
        var bytePos = doc.byteOffsetAt(params.position);
        var args = ["--display", '$filePath@$bytePos@usage'];
        var stdin = if (doc.saved) null else doc.content;
        context.callDisplay(args, stdin, cancelToken, function(data) {
            if (cancelToken.canceled)
                return;

            var xml = try Xml.parse(data).firstElement() catch (e:Dynamic) null;
            if (xml == null)
                return reject(0, "");

            var positions = [for (el in xml.elements()) el.firstChild().nodeValue];
            if (positions.length == 0)
                return reject(0, "no info");

            var results = [];
            for (p in positions) {
                var pos = HaxePosition.parse(p);
                if (pos == null) {
                    trace("Got invalid position: " + p);
                    continue;
                }
                results.push({
                    uri: fsPathToUri(getProperFileNameCase(pos.file)),
                    range: pos.toRange(),
                });
            }

            if (results.length == 0)
                reject(0, "no info");
            else
                resolve(results);
        });
    }
}

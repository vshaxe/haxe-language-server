package features;

import haxe.extern.EitherType;
using StringTools;

import vscode.BasicTypes;
import vscode.ProtocolTypes;
import jsonrpc.Protocol;
import jsonrpc.ErrorCodes.internalError;

import Uri.*;
import FsUtils.getProperFileNameCase;
import SignatureHelper.*;

class GotoDefinitionFeature extends Feature {
    override function init() {
        context.protocol.onGotoDefinition = onGotoDefinition;
    }

    function onGotoDefinition(params:TextDocumentPositionParams, cancelToken:CancelToken, resolve:EitherType<Location,Array<Location>>->Void, reject:RejectHandler) {
        var doc = context.getDocument(params.textDocument.uri);
        var filePath = uriToFsPath(params.textDocument.uri);
        var bytePos = doc.byteOffsetAt(params.position);
        var args = ["--display", '$filePath@$bytePos@position'];
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
            for (p in positions) {
                var pos = HaxePosition.parse(p);
                if (pos == null) {
                    trace("Got invalid position: " + p);
                    continue;
                }
                results.push({
                    uri: fsPathToUri(getProperFileNameCase(pos.file)),
                    range: pos.toRange(null), // no cache because this right now only returns one position
                });
            }

            return resolve(results);
        });
    }
}

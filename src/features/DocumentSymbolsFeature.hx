package features;

import vscode.BasicTypes;
import vscode.ProtocolTypes;
import jsonrpc.Protocol.CancelToken;
import jsonrpc.ErrorCodes;

import Uri.uriToFsPath;

class DocumentSymbolsFeature extends Feature {
    override function init() {
        context.protocol.onDocumentSymbols = onDocumentSymbols;
    }

    function onDocumentSymbols(params:DocumentSymbolParams, cancelToken:CancelToken, resolve:Array<SymbolInformation>->Void, reject:Int->String->Void) {
        var doc = context.getDocument(params.textDocument.uri);
        var filePath = uriToFsPath(params.textDocument.uri);
        var args = [
            "--display", '$filePath@0@document-symbols'
        ];
        var stdin = if (doc.saved) null else doc.content;
        context.callDisplay(args, stdin, cancelToken, function(data) {
            if (cancelToken.canceled)
                return;

            var data:Array<{name:String, kind:Int, location:String, ?containerName:String}> =
                try haxe.Json.parse(data) catch (e:Dynamic) {
                    trace("INVALID document-symbols: " + e);
                    trace("First 4096 symbols:\n" + data.substr(0, 4096));
                    return reject(ErrorCodes.InternalError, "Error parsing document symbol response: " + e);
                }

            var result = new Array<SymbolInformation>();
            for (v in data) {
                var pos = HaxePosition.parse(v.location);
                if (pos == null) {
                    context.protocol.sendShowMessage({type: Error, message: "Couldn't parse position for " + haxe.Json.stringify(v)});
                    continue;
                }
                var item:SymbolInformation = {
                    name: v.name,
                    kind: cast v.kind,
                    location: {
                        uri: params.textDocument.uri, // should be the same i guess
                        range: pos.toRange()
                    }
                };
                if (v.containerName != null)
                    item.containerName = v.containerName;
                result.push(item);
            }

            resolve(result);
        });
    }
}

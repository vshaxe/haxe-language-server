package features;

using StringTools;

import vscode.BasicTypes;
import vscode.ProtocolTypes;
import jsonrpc.Protocol.CancelToken;

import Uri.uriToFsPath;
import SignatureHelper.*;

class SignatureHelpFeature extends Feature {
    override function init() {
        context.protocol.onSignatureHelp = onSignatureHelp;
    }

    function onSignatureHelp(params:TextDocumentPositionParams, cancelToken:CancelToken, resolve:SignatureHelp->Void, reject:Int->String->Void) {
        var doc = context.getDocument(params.textDocument.uri);
        var filePath = uriToFsPath(params.textDocument.uri);
        var bytePos = doc.byteOffsetAt(params.position);
        var args = ["--display", '$filePath@$bytePos'];
        var stdin = if (doc.saved) null else doc.content;
        callDisplay(args, stdin, cancelToken, function(data) {
            if (cancelToken.canceled)
                return;

            var xml = try Xml.parse(data).firstElement() catch (e:Dynamic) null;
            if (xml == null)
                return reject(0, "");

            var text = xml.firstChild().nodeValue.trim();
            var signature:SignatureInformation;
            switch (parseDisplayType(text)) {
                case DTFunction(args, ret):
                    signature = {
                        label: printFunctionSignature(args, ret),
                        parameters: [for (arg in args) {label: printFunctionArgument(arg)}],

                    }
                default:
                    signature = {label: text}; // this should not happen
            }

            resolve({
                signatures: [signature],
                activeSignature: 0,
                activeParameter: 0,
            });
        });
    }
}

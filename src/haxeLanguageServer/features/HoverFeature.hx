package haxeLanguageServer.features;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.helper.TypeHelper.*;
import haxeLanguageServer.server.Protocol;

class HoverFeature {
    var context:Context;

    public function new(context) {
        this.context = context;
        context.protocol.onRequest(Methods.Hover, onHover);
    }

    function onHover(params:TextDocumentPositionParams, token:CancellationToken, resolve:Hover->Void, reject:ResponseError<NoData>->Void) {
        var doc = context.documents.get(params.textDocument.uri);
        var bytePos = context.displayOffsetConverter.characterOffsetToByteOffset(doc.content, doc.offsetAt(params.position));
        if (context.haxeServer.supportsJsonRpc && context.haxeServer.capabilities.hoverProvider) {
            var args = [context.haxeServer.createRequest(HaxeMethods.Hover, {file: doc.fsPath, offset: bytePos})];
            context.callDisplay(args, doc.content, token, function(result) {
                var hover:HoverResult = switch (result) {
                    case DCancelled:
                        resolve(null);
                        return;
                    case DResult(data):
                        haxe.Json.parse(data).result;
                }
                var content = if (hover.type != null) {
                    var printer = new haxe.rtti.JsonModuleTypesPrinter();
                    printer.printType(hover.type);
                } else {
                    return resolve(null);
                }
                var documentation = hover.documentation == null ? "" : hover.documentation;
                var result:Hover = {
                    contents: {
                        kind: MarkupKind.MarkDown,
                        value: '```haxe\n${content}\n```\n${documentation}'
                    }
                };
                result.range = hover.range;
                resolve(result);
            }, function(error) reject(ResponseError.internalError(error)));
        } else {
            var args = ['${doc.fsPath}@$bytePos@type'];
            context.callDisplay(args, doc.content, token, function(r) {
                switch (r) {
                    case DCancelled:
                        resolve(null);
                    case DResult(data):
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
                                        printFunctionDeclaration(args, ret, {argumentTypeHints: true, returnTypeHint: Always, useArrowSyntax: false, prefixPackages: false});
                                    case DTValue(type):
                                        if (type == null) "unknown" else type;
                                };

                                var d = xml.get("d");
                                d = if (d == null) "" else DocHelper.markdownFormat(d);
                                var result:Hover = {
                                    contents: {
                                        kind: MarkupKind.MarkDown,
                                        value: '```haxe\n${type}\n```\n${d}'
                                    }
                                };
                                var p = HaxePosition.parse(xml.get("p"), doc, null, context.displayOffsetConverter);
                                if (p != null)
                                    result.range = p.range;

                                resolve(result);
                        }
                }
            }, function(error) reject(ResponseError.internalError(error)));
        }
    }
}

package haxeLanguageServer.features;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.helper.TypeHelper.*;
import haxeLanguageServer.protocol.helper.DisplayPrinter;
import haxeLanguageServer.protocol.Display;

class HoverFeature {
    final context:Context;

    public function new(context) {
        this.context = context;
        context.protocol.onRequest(Methods.Hover, onHover);
    }

    function onHover(params:TextDocumentPositionParams, token:CancellationToken, resolve:Hover->Void, reject:ResponseError<NoData>->Void) {
        var doc = context.documents.get(params.textDocument.uri);
        var handle = if (context.haxeServer.supports(DisplayMethods.Hover)) handleJsonRpc else handleLegacy;
        handle(params, token, resolve, reject, doc, doc.offsetAt(params.position));
    }

    function handleJsonRpc(params:TextDocumentPositionParams, token:CancellationToken, resolve:Hover->Void, reject:ResponseError<NoData>->Void, doc:TextDocument, offset:Int) {
        context.callHaxeMethod(DisplayMethods.Hover, {file: doc.fsPath, contents: doc.content, offset: offset}, token, hover -> {
            resolve(createHover(printContent(hover), hover.item.getDocumentation(), hover.range));
            return null;
        }, error -> reject(ResponseError.internalError(error)));
    }

    function printContent<T>(hover:CompletionItemUsage<T>):String {
        var printer = new DisplayPrinter(true);
        var item = hover.item;
        var concreteType = hover.item.type;
        return switch (item.kind) {
            case Type:
                printCodeBlock(printer.printEmptyTypeDefinition(hover.item.args), Haxe);
            case Local:
                var languageId = if (item.args.origin == Argument) HaxeArgument else Haxe;
                var origin = printer.printLocalOrigin(item.args.origin);
                printCodeBlock(printer.printLocalDefinition(hover.item.args, concreteType), languageId) + '\n*$origin*';
            case ClassField:
                var result = printCodeBlock(printer.printClassFieldDefinition(item.args, concreteType, item.kind == EnumAbstractField), Haxe);
                var origin = printer.printClassFieldOrigin(item.args.origin, item.kind, "");
                switch (origin) {
                    case Some(v): result += '\n*$v*';
                    case None:
                }
                result;
            case Metadata:
                printCodeBlock("@" + item.args.name, Haxe);
            case _:
                printCodeBlock(printer.printType(concreteType), HaxeType);
        }
    }

    function handleLegacy(params:TextDocumentPositionParams, token:CancellationToken, resolve:Hover->Void, reject:ResponseError<NoData>->Void, doc:TextDocument, offset:Int) {
        var bytePos = context.displayOffsetConverter.characterOffsetToByteOffset(doc.content, offset);
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
                                    printFunctionType(args, ret);
                                case DTValue(type):
                                    if (type == null) "unknown" else type;
                            };
                            var documentation = xml.get("d");
                            var p = HaxePosition.parse(xml.get("p"), doc, null, context.displayOffsetConverter);
                            var range:Range = null;
                            if (p != null)
                                range = p.range;
                            resolve(createHover(printCodeBlock(type, HaxeType), documentation, range));
                    }
            }
        }, function(error) reject(ResponseError.internalError(error)));
    }

    function createHover(content:String, ?documentation:String, ?range:Range):Hover {
        documentation = if (documentation == null) "" else "\n" + DocHelper.markdownFormat(documentation);
        var hover:Hover = {
            contents: {
                kind: MarkupKind.MarkDown,
                value: '$content\n$documentation'
            }
        };
        if (range != null)
            hover.range = range;
        return hover;
    }

    function printCodeBlock(content:String, languageId:LanguageId):String {
        return '```$languageId\n$content```';
    }
}

private enum abstract LanguageId(String) to String {
    var Haxe = "haxe";
    var HaxeType = "haxe.type";
    var HaxeArgument = "haxe.argument";
}

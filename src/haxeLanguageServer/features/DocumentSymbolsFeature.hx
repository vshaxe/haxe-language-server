package haxeLanguageServer.features;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types;

@:enum
private abstract ModuleSymbolKind(Int) {
    var MClass = 1;
    var MInterface = 2;
    var MEnum = 3;
    var MTypedef = 4;
    var MAbstract = 5;
    var MField = 6;
    var MProperty = 7;
    var MMethod = 8;
    var MConstructor = 9;
    var MFunction = 10;
    var MVariable = 11;
}

private typedef ModuleSymbolEntry = {
    var name:String;
    var kind:ModuleSymbolKind;
    var range:Range;
    @:optional var containerName:String;
}

private typedef SymbolReply = {
    var file:String;
    var symbols:Array<ModuleSymbolEntry>;
}

class DocumentSymbolsFeature {
    var context:Context;

    public function new(context) {
        this.context = context;
        context.protocol.onRequest(Methods.DocumentSymbols, onDocumentSymbols);
        context.protocol.onRequest(Methods.WorkspaceSymbols, onWorkspaceSymbols);
    }

    function processSymbolsReply(data:String, reject:ResponseError<NoData> -> Void) {
        var data:Array<SymbolReply> =
            try haxe.Json.parse(data)
            catch (e:Any) {
                reject(ResponseError.internalError("Error parsing document symbol response: " + Std.string(e)));
                return [];
            }

        var result = [];
        for (file in data) {
            var uri = Uri.fsPathToUri(HaxePosition.getProperFileNameCase(file.file));
            for (symbol in file.symbols) {
                if (symbol.range == null) {
                    context.sendShowMessage(Error, "Unknown location for " + haxe.Json.stringify(symbol));
                    continue;
                }
                result.push(moduleSymbolEntryToSymbolInformation(symbol, uri));
            }
        }
        return result;
    }

    function makeRequest(args:Array<String>, doc:Null<TextDocument>, token:CancellationToken, resolve:Array<SymbolInformation>->Void, reject:ResponseError<NoData>->Void) {
        context.callDisplay(args, doc == null ? null : doc.content, token, function(data) {
            if (token.canceled)
                return;
            var result = processSymbolsReply(data, reject);
            resolve(result);
        }, function(error) reject(ResponseError.internalError(error)));
    }

    function onDocumentSymbols(params:DocumentSymbolParams, token:CancellationToken, resolve:Array<SymbolInformation>->Void, reject:ResponseError<NoData>->Void) {
        var doc = context.documents.get(params.textDocument.uri);
        var args = ["--display", '${doc.fsPath}@0@module-symbols'];
        makeRequest(args, doc, token, resolve, reject);
    }

    function onWorkspaceSymbols(params:WorkspaceSymbolParams, token:CancellationToken, resolve:Array<SymbolInformation>->Void, reject:ResponseError<NoData>->Void) {
        var args = ["--display ?@0@workspace-symbols@" + params.query];
        makeRequest(args, null, token, resolve, reject);
    }

    function moduleSymbolEntryToSymbolInformation(entry:ModuleSymbolEntry, uri:String):SymbolInformation {
        var result:SymbolInformation = {
            name: entry.name,
            kind: switch (entry.kind) {
                case MClass | MAbstract: SymbolKind.Class;
                case MInterface | MTypedef: SymbolKind.Interface;
                case MEnum: SymbolKind.Enum;
                case MConstructor: SymbolKind.Constructor;
                case MField: SymbolKind.Field;
                case MMethod: SymbolKind.Method;
                case MFunction: SymbolKind.Function;
                case MProperty: SymbolKind.Property;
                case MVariable: SymbolKind.Variable;
            },
            location: {
                uri: uri,
                range: entry.range
            }
        };
        if (entry.containerName != null)
            result.containerName = entry.containerName;
        return result;
    }
}

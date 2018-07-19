package haxeLanguageServer.features;

import haxeLanguageServer.tokentree.DocumentSymbolsResolver;
import haxe.extern.EitherType;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

private enum abstract ModuleSymbolKind(Int) {
    var MClass = 1;
    var MInterface;
    var MEnum;
    var MTypedef;
    var MAbstract;
    var MField;
    var MProperty;
    var MMethod;
    var MConstructor;
    var MFunction;
    var MVariable;
}

private typedef ModuleSymbolEntry = {
    var name:String;
    var kind:ModuleSymbolKind;
    var range:Range;
    var ?containerName:String;
}

private typedef SymbolReply = {
    var file:FsPath;
    var symbols:Array<ModuleSymbolEntry>;
}

class DocumentSymbolsFeature {
    final context:Context;

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
            var uri = HaxePosition.getProperFileNameCase(file.file).toUri();
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

    function makeRequest(label:String, args:Array<String>, doc:Null<TextDocument>, token:CancellationToken, resolve:Array<SymbolInformation>->Void, reject:ResponseError<NoData>->Void) {
        context.callDisplay(label, args, doc == null ? null : doc.content, token, function(r) {
            switch (r) {
                case DCancelled:
                    resolve(null);
                case DResult(data):
                    var result = processSymbolsReply(data, reject);
                    resolve(result);
            }
        }, function(error) reject(ResponseError.internalError(error)));
    }

    function onDocumentSymbols(params:DocumentSymbolParams, token:CancellationToken, resolve:Array<EitherType<SymbolInformation,DocumentSymbol>>->Void, reject:ResponseError<NoData>->Void) {
        var doc = context.documents.get(params.textDocument.uri);
        var resolver = new DocumentSymbolsResolver(doc);
        return resolve(resolver.resolve());
    }

    function onWorkspaceSymbols(params:WorkspaceSymbolParams, token:CancellationToken, resolve:Array<SymbolInformation>->Void, reject:ResponseError<NoData>->Void) {
        var args = ["?@0@workspace-symbols@" + params.query];
        makeRequest("@workspace-symbols", args, null, token, resolve, reject);
    }

    function moduleSymbolEntryToSymbolInformation(entry:ModuleSymbolEntry, uri:DocumentUri):SymbolInformation {
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

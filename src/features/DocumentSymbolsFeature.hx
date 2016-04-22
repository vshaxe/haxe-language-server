package features;

import vscode.BasicTypes;
import vscode.ProtocolTypes;
import jsonrpc.Protocol;
import jsonrpc.ErrorCodes;

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

class DocumentSymbolsFeature extends Feature {
    override function init() {
        context.protocol.onDocumentSymbols = onDocumentSymbols;
    }

    function onDocumentSymbols(params:DocumentSymbolParams, token:RequestToken, resolve:Array<SymbolInformation>->Void, reject:RejectHandler) {
        var doc = context.documents.get(params.textDocument.uri);
        var args = ["--display", '${doc.fsPath}@0@module-symbols'];
        var stdin = if (doc.saved) null else doc.content;
        callDisplay(args, stdin, token, function(data) {
            if (token.canceled)
                return;

            var data:Array<ModuleSymbolEntry> =
                try haxe.Json.parse(data)
                catch (e:Dynamic) return reject(ErrorCodes.internalError("Error parsing document symbol response: " + e));

            var result = [];
            for (entry in data) {
                if (entry.range == null) {
                    context.protocol.sendShowMessage({type: Error, message: "Unknown location for " + haxe.Json.stringify(entry)});
                    continue;
                }
                result.push(moduleSymbolEntryToSymbolInformation(entry, doc));
            }
            resolve(result);
        });
    }

    function moduleSymbolEntryToSymbolInformation(entry:ModuleSymbolEntry, document:TextDocument):SymbolInformation {
        inline function bytePosToCharPos(p) {
            var line = document.lineAt(p.line);
            return {line: p.line, character: HaxePosition.byteOffsetToCharacterOffset(line, p.character)};
        }
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
                uri: document.uri,
                range: {
                    start: bytePosToCharPos(entry.range.start),
                    end: bytePosToCharPos(entry.range.end),
                }
            }
        };
        if (entry.containerName != null)
            result.containerName = entry.containerName;
        return result;
    }
}

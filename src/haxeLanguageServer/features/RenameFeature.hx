package haxeLanguageServer.features;

import haxeLanguageServer.hxParser.LocalUsageResolver;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

class RenameFeature {
    var context:Context;

    public function new(context:Context) {
        this.context = context;
        context.protocol.onRequest(Methods.Rename, onRename);
    }

    function onRename(params:RenameParams, token:CancellationToken, resolve:WorkspaceEdit->Void, reject:ResponseError<NoData>->Void) {
        context.gotoDefinition.onGotoDefinition(params, token,
            function(locations:Array<Location>) {
                var doc = context.documents.get(params.textDocument.uri);
                var declaration = locations[0];
                if (declaration.uri != params.textDocument.uri) {
                    return reject(ResponseError.internalError("Can only rename locals"));
                }

                var declarationRange = declaration.range;
                var resolver = new LocalUsageResolver(declarationRange);
                resolver.walkFile(doc.parseTree, Root);

                var changes = new haxe.DynamicAccess();
                changes[params.textDocument.uri.toString()] = [
                    for (usage in resolver.usages) {{
                            range: usage,
                            newText: params.newName
                        }
                    }
                ];
                resolve({changes: changes});
            },
            function(_) {
                // TODO
                reject(ResponseError.internalError("You cannot rename this element"));
            }
        );
    }
}
package haxeLanguageServer.features;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import vscodeProtocol.Types;

class CodeLensFeature {
    var context:Context;

    public function new(context:Context) {
        this.context = context;
        context.protocol.onCodeLens = onCodeLens;
    }

    public function updateStatistics(doc:TextDocument, f:Void -> Void) {

    }

    function getCodeLensFromStatistics(uri:String, fileStatistics:FileStatistics) {
        var actions:Array<CodeLens> = [];
        function addRelation(kind:String, plural:String, relations:Array<Relation>) {
            for (relation in relations) {
                var args:Array<Dynamic> = [
                    uri,
                    relation.range.start,
                    relation.relations.map(function(c) {
                        // avoid being positioned at the end of a declaration when navigating to it
                        var range = { start: c.range.start, end: c.range.start };
                        return { range: range, uri: Uri.fsPathToUri(c.file) }
                    })
                ];
                actions.push({
                    command: {
                        title: relation.relations.length + " " + kind + (relation.relations.length > 1 ? plural : ""),
                        command: "haxe.showReferences",
                        arguments: args
                    },
                    range: relation.range
                });
            }
        }
        addRelation("implementer", "s", fileStatistics.implementer);
        addRelation("subclass", "es", fileStatistics.subclasses);
        addRelation("overridde", "s", fileStatistics.overrides);
        addRelation("reference", "s", fileStatistics.fieldReferences);
        return actions;
    }

    function onCodeLens(params:CodeLensParams, token:CancellationToken, resolve:Array<CodeLens> -> Void, reject:ResponseError<NoData>->Void) {
        if (!context.config.enableCodeLens) {
            return;
        }
        var doc = context.documents.get(params.textDocument.uri);
        function processError(error:String) {
            context.protocol.sendLogMessage({type: Error, message: error});
        }
        function processStatisticsReply(s:String) {
            var data:Array<Statistics> =
                try haxe.Json.parse(s)
                catch (e:Any) {
                    trace("Error parsing stats response: " + Std.string(e));
                    return;
                }
            for (statistics in data) {
                var uri = Uri.fsPathToUri(statistics.file);
                if (uri == params.textDocument.uri) {
                    resolve(getCodeLensFromStatistics(uri, statistics.statistics));
                }
            }
        }
        context.callDisplay(["--display", doc.fsPath + "@0@statistics"], doc.content, null, processStatisticsReply, processError);
    }
}

private typedef Relation = {
    var range:Range;
    var relations:Array<{file:String, range:Range}>;
}

private typedef FileStatistics = {
    var implementer:Array<Relation>;
    var subclasses:Array<Relation>;
    var overrides:Array<Relation>;
    var fieldReferences:Array<Relation>;
}

private typedef Statistics = {
    var file:String;
    var statistics:FileStatistics;
}
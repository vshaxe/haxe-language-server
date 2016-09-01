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
        function addClassRelation(kind:String, relations:Array<ClassRelation>) {
            for (relation in relations) {
                var args:Array<Dynamic> = [
                    uri,
                    relation.range.start,
                    relation.classes.map(function(c) return { range: c.range, uri: Uri.fsPathToUri(c.file) })
                ];
                actions.push({
                    command: {
                        title: relation.classes.length + " " + kind,
                        command: "haxe.showReferences",
                        arguments: args
                    },
                    range: relation.range
                });
            }
        }
        addClassRelation("implementers", fileStatistics.implementer);
        addClassRelation("sub classes", fileStatistics.subclasses);
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

private typedef ClassRelation = {
    var range:Range;
    var classes:Array<{file:String, range:Range}>;
}

private typedef FileStatistics = {
    var implementer:Array<ClassRelation>;
    var subclasses:Array<ClassRelation>;
}

private typedef Statistics = {
    var file:String;
    var statistics:FileStatistics;
}
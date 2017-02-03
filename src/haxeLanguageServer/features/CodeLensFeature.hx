package haxeLanguageServer.features;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

class CodeLensFeature {
    var context:Context;

    public function new(context:Context) {
        this.context = context;
        context.protocol.onRequest(Methods.CodeLens, onCodeLens);
    }

    function getCodeLensFromStatistics(uri:String, statistics:Array<StatisticsObject>) {
        var actions:Array<CodeLens> = [];
        function addRelation(kind:String, plural:String, range:Range, relations:Null<Array<Relation>>) {
            if (relations == null) {
                relations = [];
            }
            var title = relations.length + " " + kind + (relations.length == 1 ? "" : plural);
            var action = if (relations.length == 0) {
                {
                    command: {
                        title: title,
                        command: "",
                        arguments: []
                    },
                    range: range
                };
            } else {
                var args:Array<Dynamic> = [
                    uri,
                    range.start,
                    relations.map(function(c) {
                        var cRange = c.range;
                        // multi-line ranges are not useful, VSCode navigates to the end of them
                        if (c.range.start.line != c.range.end.line) {
                            var nextLineStart = { character: 0, line: c.range.start.line + 1 };
                            cRange = { start: c.range.start, end: nextLineStart };
                        }
                        return { range: cRange, uri: Uri.fsPathToUri(c.file) }
                    })
                ];
                {
                    command: {
                        title: title,
                        command: "haxe.showReferences",
                        arguments: args
                    },
                    range: range
                };
            }
            actions.push(action);
        }
        for (statistic in statistics) {
            if (statistic.kind == null) {
                continue; // Shouldn't happen, but you never know
            }
            var range = statistic.range;
            switch (statistic.kind) {
                case ClassType:
                    addRelation("subclass", "es", range, statistic.subclasses);
                case InterfaceType:
                    addRelation("implementer", "s", range, statistic.implementers);
                    addRelation("subinterface", "s", range, statistic.subclasses);
                case EnumType:
                    addRelation("reference", "s", range, statistic.references);
                case EnumField:
                    addRelation("reference", "s", range, statistic.references);
                case ClassField:
                    if (statistic.overrides != null) addRelation("override", "s", range, statistic.overrides);
                    addRelation("reference", "s", range, statistic.references);
                    if (statistic.implementers != null) addRelation("implementation", "s", range, statistic.implementers);
            }
        }
        return actions;
    }

    function onCodeLens(params:CodeLensParams, token:CancellationToken, resolve:Array<CodeLens>->Void, reject:ResponseError<NoData>->Void) {
        if (!context.config.enableCodeLens)
            return resolve([]);

        var doc = context.documents.get(params.textDocument.uri);
        function processError(error:String) {
            context.sendLogMessage(Log, error);
        }
        function processStatisticsReply(s:String) {
            var data:Array<Statistics> =
                try
                    haxe.Json.parse(s)
                catch (e:Any)
                    return reject(ResponseError.internalError("Error parsing stats response: " + Std.string(e)));
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

@:enum abstract StatisticObjectKind(String) {
    var ClassType = "class type";
    var InterfaceType = "interface type";
    var EnumType = "enum type";
    var ClassField = "class field";
    var EnumField = "enum field";
}

private typedef Relation = {
    var file:String;
    var range:Range;
}

private typedef StatisticsObject = {
    var range:Range;
    @:optional var kind:StatisticObjectKind;
    @:optional var implementers:Array<Relation>;
    @:optional var subclasses:Array<Relation>;
    @:optional var overrides:Array<Relation>;
    @:optional var references:Array<Relation>;
}

private typedef Statistics = {
    var file:String;
    var statistics:Array<StatisticsObject>;
}
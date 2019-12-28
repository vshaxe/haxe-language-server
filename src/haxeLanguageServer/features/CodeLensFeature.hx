package haxeLanguageServer.features;

import haxeLanguageServer.server.DisplayResult;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

class CodeLensFeature {
	final context:Context;

	public function new(context:Context) {
		this.context = context;

		context.registerCapability({
			id: CodeLensRequest.type,
			method: CodeLensRequest.type
		});
		context.languageServerProtocol.onRequest(CodeLensRequest.type, onCodeLens);
	}

	function getCodeLensFromStatistics(uri:DocumentUri, statistics:Array<StatisticsObject>) {
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
							var nextLineStart = {character: 0, line: c.range.start.line + 1};
							cRange = {start: c.range.start, end: nextLineStart};
						}
						return {range: cRange, uri: c.file.toUri()}
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
			switch statistic.kind {
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
					if (statistic.overrides != null)
						addRelation("override", "s", range, statistic.overrides);
					addRelation("reference", "s", range, statistic.references);
					if (statistic.implementers != null)
						addRelation("implementation", "s", range, statistic.implementers);
			}
		}
		return actions;
	}

	function onCodeLens(params:CodeLensParams, token:CancellationToken, resolve:Array<CodeLens>->Void, reject:ResponseError<NoData>->Void) {
		if (!context.config.user.enableCodeLens) {
			return resolve([]);
		}
		var uri = params.textDocument.uri;
		if (!uri.isFile()) {
			return reject.notAFile();
		}
		var doc:Null<TextDocument> = context.documents.get(uri);
		if (doc == null) {
			return reject.documentNotFound(uri);
		}
		context.callDisplay("@statistics", [doc.uri.toFsPath() + "@0@statistics"], doc.content, token, function(r:DisplayResult) {
			switch r {
				case DCancelled:
					resolve(null);
				case DResult(s):
					var data:Array<Statistics> = try haxe.Json.parse(s) catch (e:Any) return reject(ResponseError.internalError("Error parsing stats response: "
						+ Std.string(e)));
					for (statistics in data) {
						var currentUri = statistics.file.toUri();
						if (currentUri == uri) {
							return resolve(getCodeLensFromStatistics(uri, statistics.statistics));
						}
					}
			}
		}, reject.handler());
	}
}

private enum abstract StatisticObjectKind(String) {
	var ClassType = "class type";
	var InterfaceType = "interface type";
	var EnumType = "enum type";
	var ClassField = "class field";
	var EnumField = "enum field";
}

private typedef Relation = {
	var file:FsPath;
	var range:Range;
}

private typedef StatisticsObject = {
	var range:Range;
	var ?kind:StatisticObjectKind;
	var ?implementers:Array<Relation>;
	var ?subclasses:Array<Relation>;
	var ?overrides:Array<Relation>;
	var ?references:Array<Relation>;
}

private typedef Statistics = {
	var file:FsPath;
	var statistics:Array<StatisticsObject>;
}

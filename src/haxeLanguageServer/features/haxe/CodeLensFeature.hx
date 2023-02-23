package haxeLanguageServer.features.haxe;

import haxeLanguageServer.server.DisplayResult;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.CodeLens;

class CodeLensFeature {
	final context:Context;
	final cache = new Map<DocumentUri, Array<CodeLens>>();

	public function new(context:Context) {
		this.context = context;

		context.registerCapability(CodeLensRequest.type, {documentSelector: Context.haxeSelector});
		context.languageServerProtocol.onRequest(CodeLensRequest.type, onCodeLens);
	}

	function getCodeLensFromStatistics(uri:DocumentUri, statistics:Array<StatisticsObject>) {
		final actions:Array<CodeLens> = [];
		function addRelation(kind:String, plural:String, range:Range, relations:Null<Array<Relation>>) {
			if (relations == null) {
				relations = [];
			}
			final title = relations.length + " " + kind + (relations.length == 1 ? "" : plural);
			final action = if (relations.length == 0) {
				{
					command: {
						title: title,
						command: "",
						arguments: []
					},
					range: range
				};
			} else {
				final args:Array<Dynamic> = [
					uri,
					range.start,
					relations.filter(function(c) {
						// HaxeFoundation/haxe#9092
						return c.range != null;
					}).map(function(c) {
						var cRange = c.range;
						// multi-line ranges are not useful, VSCode navigates to the end of them
						if (c.range.start.line != c.range.end.line) {
							final nextLineStart = {character: 0, line: c.range.start.line + 1};
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
			final range = statistic.range;
			switch statistic.kind {
				case ClassType:
					if (statistic.subclasses != null) {
						addRelation("subclass", "es", range, statistic.subclasses);
					}
				case InterfaceType:
					addRelation("implementation", "s", range, statistic.implementers);
					if (statistic.subclasses != null) {
						addRelation("subinterface", "s", range, statistic.subclasses);
					}
				case EnumType:
					addRelation("reference", "s", range, statistic.references);
				case EnumField:
					addRelation("reference", "s", range, statistic.references);
				case ClassField:
					if (statistic.overrides != null) {
						addRelation("override", "s", range, statistic.overrides);
					}
					addRelation("reference", "s", range, statistic.references);
					if (statistic.implementers != null) {
						addRelation("implementation", "s", range, statistic.implementers);
					}
			}
		}
		return actions;
	}

	function onCodeLens(params:CodeLensParams, token:CancellationToken, resolve:Array<CodeLens>->Void, reject:ResponseError<NoData>->Void) {
		if (context.config.user.enableCodeLens == false) {
			return resolve([]);
		}
		final uri = params.textDocument.uri;
		final doc:Null<HaxeDocument> = context.documents.getHaxe(uri);
		if (doc == null || !uri.isFile()) {
			return reject.noFittingDocument(uri);
		}
		final onResolve = context.startTimer("@statistics");
		context.callDisplay("@statistics", [doc.uri.toFsPath() + "@0@statistics"], doc.content, token, function(r:DisplayResult) {
			switch r {
				case DCancelled:
					resolve([]);
				case DResult(s):
					final data:Array<Statistics> = try {
						haxe.Json.parse(s);
					} catch (e) {
						return reject(ResponseError.internalError('Error parsing stats response'));
					}
					onResolve(data);
					for (statistics in data) {
						final currentUri = statistics.file.toUri();
						if (currentUri == uri) {
							final codeLens = getCodeLensFromStatistics(uri, statistics.statistics);
							cache[uri] = codeLens;
							resolve(codeLens);
						}
					}
			}
		}, function(error) {
			final lens = cache[uri];
			if (lens != null) {
				resolve(lens);
				trace('Reusing cached code lens - failed with:\n\t$error');
			} else {
				reject(ResponseError.internalError(error));
			}
		});
	}
}

private enum abstract StatisticObjectKind(String) {
	final ClassType = "class type";
	final InterfaceType = "interface type";
	final EnumType = "enum type";
	final ClassField = "class field";
	final EnumField = "enum field";
}

private typedef Relation = {
	final file:FsPath;
	final range:Range;
}

private typedef StatisticsObject = {
	final range:Range;
	final ?kind:StatisticObjectKind;
	final ?implementers:Array<Relation>;
	final ?subclasses:Array<Relation>;
	final ?overrides:Array<Relation>;
	final ?references:Array<Relation>;
}

private typedef Statistics = {
	final file:FsPath;
	final statistics:Array<StatisticsObject>;
}

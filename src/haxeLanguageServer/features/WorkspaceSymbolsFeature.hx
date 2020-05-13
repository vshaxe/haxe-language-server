package haxeLanguageServer.features;

import haxeLanguageServer.helper.HaxePosition;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

private enum abstract ModuleSymbolKind(Int) {
	var Class = 1;
	var Interface;
	var Enum;
	var TypeAlias;
	var Abstract;
	var Field;
	var Property;
	var Method;
	var Constructor;
	var Function;
	var Variable;
	var Struct;
	var EnumAbstract;
	var Operator;
	var EnumMember;
	var Constant;
}

private typedef ModuleSymbolEntry = {
	var name:String;
	var kind:ModuleSymbolKind;
	var range:Range;
	var ?containerName:String;
	var ?isDeprecated:Bool;
}

private typedef SymbolReply = {
	var file:FsPath;
	var symbols:Array<ModuleSymbolEntry>;
}

class WorkspaceSymbolsFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.languageServerProtocol.onRequest(WorkspaceSymbolRequest.type, onWorkspaceSymbols);
	}

	function processSymbolsReply(data:Array<SymbolReply>, reject:ResponseError<NoData>->Void) {
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

	function makeRequest(label:String, args:Array<String>, doc:Null<TextDocument>, token:CancellationToken, resolve:Array<SymbolInformation>->Void,
			reject:ResponseError<NoData>->Void) {
		var onResolve = context.startTimer("@workspace-symbols");
		context.callDisplay(label, args, doc == null ? null : doc.content, token, function(r) {
			switch r {
				case DCancelled:
					resolve(null);
				case DResult(data):
					var data:Array<SymbolReply> = try {
						haxe.Json.parse(data);
					} catch (e) {
						reject(ResponseError.internalError("Error parsing document symbol response: " + Std.string(e)));
						return;
					}
					var result = processSymbolsReply(data, reject);
					resolve(result);
					onResolve(data, data.length + " symbols");
			}
		}, reject.handler());
	}

	function onWorkspaceSymbols(params:WorkspaceSymbolParams, token:CancellationToken, resolve:Array<SymbolInformation>->Void,
			reject:ResponseError<NoData>->Void) {
		var args = ["?@0@workspace-symbols@" + params.query];
		makeRequest("@workspace-symbols", args, null, token, resolve, reject);
	}

	function moduleSymbolEntryToSymbolInformation(entry:ModuleSymbolEntry, uri:DocumentUri):SymbolInformation {
		var result:SymbolInformation = {
			name: entry.name,
			kind: switch entry.kind {
				case Class | Abstract: SymbolKind.Class;
				case Interface | TypeAlias: SymbolKind.Interface;
				case Enum: SymbolKind.Enum;
				case Constructor: SymbolKind.Constructor;
				case Field: SymbolKind.Field;
				case Method: SymbolKind.Method;
				case Function: SymbolKind.Function;
				case Property: SymbolKind.Property;
				case Variable: SymbolKind.Variable;
				case Struct: SymbolKind.Struct;
				case EnumAbstract: SymbolKind.Enum;
				case Operator: SymbolKind.Operator;
				case EnumMember: SymbolKind.EnumMember;
				case Constant: SymbolKind.Constant;
			},
			location: {
				uri: uri,
				range: entry.range
			}
		};
		if (entry.containerName != null) {
			result.containerName = entry.containerName;
		}
		if (entry.isDeprecated != null) {
			result.deprecated = entry.isDeprecated;
		}
		return result;
	}
}

package haxeLanguageServer.features.haxe;

import haxeLanguageServer.helper.HaxePosition;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

private enum abstract ModuleSymbolKind(Int) {
	final Class = 1;
	final Interface;
	final Enum;
	final TypeAlias;
	final Abstract;
	final Field;
	final Property;
	final Method;
	final Constructor;
	final Function;
	final Variable;
	final Struct;
	final EnumAbstract;
	final Operator;
	final EnumMember;
	final Constant;
	final Module;
}

private typedef ModuleSymbolEntry = {
	final name:String;
	final kind:ModuleSymbolKind;
	final range:Range;
	final ?containerName:String;
	final ?isDeprecated:Bool;
}

private typedef SymbolReply = {
	final file:FsPath;
	final symbols:Array<ModuleSymbolEntry>;
}

class WorkspaceSymbolsFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.languageServerProtocol.onRequest(WorkspaceSymbolRequest.type, onWorkspaceSymbols);
	}

	function processSymbolsReply(data:Array<SymbolReply>, reject:ResponseError<NoData>->Void) {
		final result = [];
		for (file in data) {
			final uri = HaxePosition.getProperFileNameCase(file.file).toUri();
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

	function makeRequest(label:String, args:Array<String>, doc:Null<TextDocument>, token:Null<CancellationToken>, resolve:Array<SymbolInformation>->Void,
			reject:ResponseError<NoData>->Void) {
		final onResolve = context.startTimer("@workspace-symbols");
		context.callDisplay(label, args, doc!.content, token, function(result) {
			switch result {
				case DCancelled:
					resolve([]);
				case DResult(data):
					final data:Array<SymbolReply> = try {
						haxe.Json.parse(data);
					} catch (e) {
						reject(ResponseError.internalError("Error parsing document symbol response: " + Std.string(e)));
						return;
					}
					final result = processSymbolsReply(data, reject);
					resolve(result);
					onResolve(data, data.length + " symbols");
			}
		}, reject.handler());
	}

	public function onWorkspaceSymbols(params:WorkspaceSymbolParams, token:Null<CancellationToken>, resolve:Array<SymbolInformation>->Void,
			reject:ResponseError<NoData>->Void) {
		final args = ["?@0@workspace-symbols@" + params.query];
		makeRequest("@workspace-symbols", args, null, token, resolve, reject);
	}

	function moduleSymbolEntryToSymbolInformation(entry:ModuleSymbolEntry, uri:DocumentUri):SymbolInformation {
		final result:SymbolInformation = {
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
				case Module: SymbolKind.Module;
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

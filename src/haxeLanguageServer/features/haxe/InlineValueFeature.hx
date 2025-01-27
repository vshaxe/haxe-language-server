package haxeLanguageServer.features.haxe;

import haxeLanguageServer.features.haxe.refactoring.EditDoc;
import haxeLanguageServer.features.haxe.refactoring.EditList;
import haxeLanguageServer.features.haxe.refactoring.RefactorCache;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.InlineValue;
import languageServerProtocol.protocol.InlineValue;
import refactor.discover.Identifier;
import refactor.discover.IdentifierPos;

class InlineValueFeature {
	final context:Context;
	final refactorCache:RefactorCache;

	public final converter:Haxe3DisplayOffsetConverter;

	public function new(context:Context, refactorCache:RefactorCache) {
		this.context = context;
		this.refactorCache = refactorCache;

		converter = new Haxe3DisplayOffsetConverter();

		context.languageServerProtocol.onRequest(InlineValueRequest.type, onInlineValue);
	}

	function onInlineValue(params:InlineValueParams, token:CancellationToken, resolve:Array<InlineValue>->Void, reject:ResponseError<NoData>->Void) {
		if (context.config.user.disableRefactorCache || context.config.user.disableInlineValue) {
			resolve([]);
			return;
		}

		var file = refactorCache.fileList.getFile(params.textDocument.uri.toFsPath().toString());
		if (file == null) {
			reject.handler()("file not found");
			return;
		}

		var editDoc = new EditDoc(params.textDocument.uri.toFsPath(), new EditList(), context, converter);

		var localScopedNames:Array<String> = [];
		var outOfScope:Array<Identifier> = [];
		var functionStartLine:Int = params.context.stoppedLocation.start.line;

		function matchLocalScoped(identifier:Identifier):Bool {
			switch (identifier.name) {
				case "this" | "super":
					return false;
				default:
			}
			return switch (identifier.type) {
				case ScopedLocal(scopeStart, scopeEnd, scopeType):
					var pos:IdentifierPos = {
						fileName: identifier.pos.fileName,
						start: scopeStart,
						end: scopeEnd
					};
					var range = editDoc.posToRange(pos);
					if (!range.contains(params.context.stoppedLocation)) {
						outOfScope.push(identifier);
						return false;
					}
					localScopedNames.push(identifier.name);
					true;
				case Access:
					for (scoped in outOfScope) {
						switch (scoped.type) {
							case ScopedLocal(scopeStart, scopeEnd, scopeType):
								if ((scoped.name == identifier.name) || identifier.name.startsWith('${scoped.name}.')) {
									if (scopeStart <= identifier.pos.start && scopeEnd >= identifier.pos.end) {
										return false;
									}
								}
							default:
						}
					}
					true;
				case Method(_):
					var functionRange:Range = editDoc.posToRange(identifier.pos);
					if (functionRange.start.line <= params.context.stoppedLocation.start.line) {
						functionStartLine = functionRange.start.line;
					}
					false;
				default: false;
			}
		}
		final identifiers:Array<Identifier> = file.findAllIdentifiers(matchLocalScoped);
		final inlineValueVars:Array<InlineValue> = [];
		for (identifier in identifiers) {
			var identifierRange = editDoc.posToRange(identifier.pos);
			if (identifierRange.start.line < functionStartLine) {
				continue;
			}
			if (!params.range.contains(identifierRange)) {
				continue;
			}
			if (params.context.stoppedLocation.end.line < identifierRange.start.line) {
				continue;
			}
			var needsExpression:Bool = identifier.name.contains(".");
			if ((identifier.type == Access) && !localScopedNames.contains(identifier.name)) {
				needsExpression = true;
			}

			if (needsExpression) {
				inlineValueVars.push({
					range: identifierRange,
					expression: identifier.name
				});
			} else {
				inlineValueVars.push({
					range: identifierRange,
					variableName: identifier.name,
					caseSensitiveLookup: true
				});
			}
		}

		resolve(inlineValueVars);
	}
}

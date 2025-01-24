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

		function matchLocalScoped(identifier:Identifier):Bool {
			return switch (identifier.type) {
				case ScopedLocal(scopeStart, scopeEnd, scopeType):
					localScopedNames.push(identifier.name);
					true;
				case Access: true;
				default: false;
			}
		}
		final identifiers:Array<Identifier> = file.findAllIdentifiers(matchLocalScoped);
		final inlineValueVars:Array<InlineValue> = [];
		for (identifier in identifiers) {
			var identifierRange = editDoc.posToRange(identifier.pos);
			if (!params.range.contains(identifierRange)) {
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

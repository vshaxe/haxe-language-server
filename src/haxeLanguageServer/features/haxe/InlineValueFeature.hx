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
import refactor.discover.Type;
import tokentree.utils.TokenTreeCheckUtils;

using tokentree.TokenTreeAccessHelper;

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
		final onResolve = context.startTimer("textDocument/inlineValue");
		if (context.config.user.disableRefactorCache || context.config.user.disableInlineValue) {
			resolve([]);
			onResolve();
			return;
		}

		var file = refactorCache.fileList.getFile(params.textDocument.uri.toFsPath().toString());
		if (file == null) {
			reject.handler()("file not found");
			onResolve();
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
			if (isSharpCondition(params, identifier)) {
				continue;
			}
			if (isTypeParam(params, identifier)) {
				continue;
			}
			if (isLocalFunctionName(params, identifier)) {
				continue;
			}
			var hasDot:Bool = identifier.name.contains(".");
			if (!hasDot) {
				if (skipIdentifier(identifier)) {
					continue;
				}
			}
			inlineValueVars.push({
				range: identifierRange,
				expression: identifier.name
			});
		}

		resolve(inlineValueVars);
		onResolve();
	}

	function isSharpCondition(params:InlineValueParams, identifier:Identifier):Bool {
		final doc:Null<HaxeDocument> = context.documents.getHaxe(params.textDocument.uri);
		final token = doc?.tokens?.getTokenAtOffset(identifier.pos.start);

		if (token == null) {
			return false;
		}
		var parent = token.parent;
		while (parent != null) {
			switch (parent.tok) {
				case Dot:
				case Const(CIdent(_)):
				case POpen:
				case Unop(OpNot):
				case Binop(OpBoolAnd) | Binop(OpBoolOr):
				case Sharp("if") | Sharp("elseif"):
					return true;
				default:
					return false;
			}
			parent = parent.parent;
		}

		return false;
	}

	function isLocalFunctionName(params:InlineValueParams, identifier:Identifier):Bool {
		final doc:Null<HaxeDocument> = context.documents.getHaxe(params.textDocument.uri);
		final token = doc?.tokens?.getTokenAtOffset(identifier.pos.start);

		if (token == null) {
			return false;
		}
		switch (token.parent?.tok) {
			case Kwd(KwdFunction):
				return true;
			default:
				return false;
		}
	}

	function isTypeParam(params:InlineValueParams, identifier:Identifier):Bool {
		final doc:Null<HaxeDocument> = context.documents.getHaxe(params.textDocument.uri);
		final token = doc?.tokens?.getTokenAtOffset(identifier.pos.end);

		if (token == null) {
			return false;
		}
		var parent = token.parent;
		while (parent != null) {
			switch (parent.tok) {
				case Dot:
				case DblDot:
				case BrOpen:
				case Const(CIdent(_)):
				case Binop(OpAssign):
				case Sharp(_):
					return true;
				case Binop(OpLt):
					return parent.access().firstOf(Binop(OpGt)).exists();
				default:
					return false;
			}
			parent = parent.parent;
		}

		return false;
	}

	function skipIdentifier(identifier:Identifier):Bool {
		if (isTypeUsed(identifier.defineType, identifier.name)) {
			return true;
		}
		var allUses:Array<Identifier> = refactorCache.nameMap.getIdentifiers(identifier.name);
		for (use in allUses) {
			switch (use.type) {
				case EnumField(_):
					return true;
				default:
			}
		}
		return false;
	}

	function isTypeUsed(containerType:Null<Type>, name:String):Bool {
		if (containerType == null) {
			return false;
		}
		final types:Array<Type> = refactorCache.typeList.findTypeName(name);
		for (type in types) {
			switch (containerType.file.importsModule(type.file.getPackage(), type.file.getMainModulName(), name)) {
				case None:
				case ImportedWithAlias(_):
				case Global | ParentPackage | SamePackage | Imported | StarImported:
					return true;
			}
		}
		return false;
	}
}

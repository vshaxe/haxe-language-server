package haxeLanguageServer.features.haxe.codeAction.diagnostics;

import haxe.display.Display.HoverDisplayItemOccurence;
import haxeLanguageServer.helper.WorkspaceEditHelper;
import js.lib.Promise;
import jsonrpc.CancellationToken;
import languageServerProtocol.Types.CodeAction;
import languageServerProtocol.Types.DefinitionLink;
import languageServerProtocol.Types.Diagnostic;
import languageServerProtocol.Types.Location;
import tokentree.TokenTree;

class AddTypeHintActions {
	public static function createAddTypeHintActions(context:Context, params:CodeActionParams, existingActions:Array<CodeAction>):Array<CodeAction> {
		final uri = params.textDocument.uri;
		final doc = context.documents.getHaxe(uri) ?? return [];
		final actions:Array<CodeAction> = [];
		final token = doc.tokens!.getTokenAtOffset(doc.offsetAt(params.range.end));
		if (token == null)
			return [];

		if (token.isCIdent()) {
			final isVarDecl = isVarDecl(token);
			final isFunArg = TokenTreeUtils.isFunctionArg(token);
			final isFunName = isFunctionName(token);
			if (isVarDecl || isFunArg) {
				// check type hint
				final maybeColon = token.getFirstChild();
				if (maybeColon != null && maybeColon.matches(DblDot)) {
					return actions;
				}
			} else if (isFunName) {
				// check return type hint
				if (token.access().firstOf(DblDot) != null)
					return actions;
			} else {
				return actions;
			}
		} else {
			// action on `return` keyword
			if (!TokenTreeUtils.isInFunctionScope(token))
				return actions;
			if (!token.tok.match(Kwd(KwdReturn)))
				return actions;

			final nameToken = token.parent!.parent ?? return actions;
			// check return type hint
			if (nameToken.access().firstOf(DblDot) != null)
				return actions;
			params.range = doc.rangeAt(nameToken.pos, Utf8);
		}

		final data:CodeActionResolveData = {
			type: AddTypeHint,
			params: params,
		};
		actions.push({
			title: "Add type hint",
			data: data,
			kind: RefactorRewrite,
			isPreferred: false
		});

		return actions;
	}

	public static function createAddTypeHintAction(context:Context, action:CodeAction, params:CodeActionParams):Null<Promise<CodeAction>> {
		if ((params.context.only != null) && (!params.context.only.contains(RefactorRewrite))) {
			return null;
		}
		final document = context.documents.getHaxe(params.textDocument.uri);
		if (document == null)
			return null;
		var tokenSource = new CancellationTokenSource();

		final identToken = document.tokens!.getTokenAtOffset(document.offsetAt(params.range.end));
		if (identToken == null)
			return null;

		final referencesPromise = new Promise(function(resolve:(locations:Array<Location>) -> Void, reject) {
			context.findReferences.onFindReferences({
				textDocument: params.textDocument,
				position: document.positionAt(identToken.pos.min, Utf8)
			}, tokenSource.token, array -> {
				resolve(array ?? []);
			}, error -> reject(error));
		});

		final gotoPromise = new Promise(function(resolve:(definitions:Array<DefinitionLink>) -> Void, reject) {
			context.gotoDefinition.onGotoDefinition({
				textDocument: params.textDocument,
				position: document.positionAt(identToken.pos.min, Utf8)
			}, tokenSource.token, array -> {
				resolve(array);
			}, error -> reject(error));
		});

		function makeHoverPromise<T>(loc:Location):Promise<Null<HoverDisplayItemOccurence<T>>> {
			final fileName:String = loc.uri.toFsPath().toString();
			final locDoc = context.documents.getHaxe(loc.uri) ?? return Promise.resolve();
			var hoverPos = locDoc.offsetAt(loc.range.end) - 1;
			return MissingArgumentsAction.makeHoverRequest(context, fileName, hoverPos, tokenSource.token);
		}

		final gotoAndHoverPromise = Promise.all([gotoPromise, referencesPromise]).then(results -> {
			final definitions:Array<DefinitionLink> = results[0];
			final definition = definitions[0] ?? cast return null;
			final locations:Array<Location> = results[1];
			// use latest location for best hover, or fallback to definition
			final location = locations[locations.length - 1] ?? {
				uri: definition.targetUri,
				range: definition.targetSelectionRange
			}
				?? cast return null;
			final locDoc = context.documents.getHaxe(location.uri) ?? cast return null;
			final locToken = locDoc.tokens!.getTokenAtOffset(locDoc.offsetAt(location.range.end));
			if (locToken == null)
				return null;
			final child = locToken.getFirstChild();
			if (child != null) {
				// hover on opAssign when available
				// (`x = 1` is Int on hover, but `var x = 1` is not)
				final isVarDecl = isVarDecl(locToken);
				if (!isVarDecl && child.tok.match(Binop(OpAssign | OpAssignOp(_)))) {
					location.range = locDoc.rangeAt(child.pos, Utf8);
				}
			}

			final hoverPromise = makeHoverPromise(location);
			return Promise.all([Promise.resolve(gotoPromise), hoverPromise]);
		});

		final actionPromise = gotoAndHoverPromise.then(results -> {
			final definitions:Array<DefinitionLink> = results[0];
			final hover:HoverDisplayItemOccurence<Dynamic> = results[1];
			final definition = definitions[0] ?? return action;
			final defDoc = context.documents.getHaxe(definition.targetUri) ?? return action;
			final defToken = defDoc.tokens!.getTokenAtOffset(defDoc.offsetAt(definition.targetSelectionRange.end));
			// check if definition already has typehint
			if (defToken == null || !defToken.isCIdent())
				return action;
			final maybeColon = defToken.getFirstChild();
			if (maybeColon != null && maybeColon.matches(DblDot))
				return action;

			final isFunName = isFunctionName(defToken);
			var typeHint = MissingArgumentsAction.printTypeHint(hover.item) ?? return action;
			// trace(typeHint);
			if (isFunName) {
				// from: (arg, b:() -> Void) -> () -> Int
				// to: () -> Int
				typeHint = extractReturnType(typeHint);
			}
			if (typeHint == "?")
				return action;
			final range = if (isFunName) {
				// add return type hint
				final pOpen = defToken.access().firstOf(POpen).token ?? return action;
				final pos = pOpen.getPos();
				document.rangeAt(pos.max, pos.max, Utf8);
			} else {
				document.rangeAt(defToken.pos.max, defToken.pos.max, Utf8);
			}

			action.edit = WorkspaceEditHelper.create(defDoc, [{range: range, newText: ':$typeHint'}]);
			return action;
		});

		return actionPromise;
	}

	static function isVarDecl(identToken:TokenTree):Bool {
		final parent = identToken.parent ?? return false;
		return parent.tok.match(Kwd(KwdVar | KwdFinal));
	}

	static function isFunctionName(nameToken:TokenTree):Bool {
		final parent = nameToken.parent ?? return false;
		return parent.tok.match(Kwd(KwdFunction));
	}

	static function extractReturnType(hint:String):String {
		if (hint.length == 0 || hint.charCodeAt(0) != "(".code)
			return hint;
		var pOpens = 0;
		for (i => code in hint) {
			switch code {
				case "(".code:
					pOpens++;
				case ")".code:
					pOpens--;
					if (pOpens != 0)
						continue;
					final part = hint.substr(i + 1).trim();
					if (part.startsWith("->")) {
						return part.substr(2).ltrim();
					} else {
						return hint;
					}
			}
		}
		return hint;
	}
}

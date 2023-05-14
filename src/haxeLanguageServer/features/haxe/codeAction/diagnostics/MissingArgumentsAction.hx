package haxeLanguageServer.features.haxe.codeAction.diagnostics;

import haxe.display.Display.DisplayItem;
import haxe.display.Display.DisplayMethods;
import haxe.display.Display.HoverDisplayItemOccurence;
import haxe.display.JsonModuleTypes.JsonType;
import haxeLanguageServer.features.haxe.InlayHintFeature.HoverRequestContext;
import haxeLanguageServer.protocol.DisplayPrinter;
import js.lib.Promise;
import jsonrpc.CancellationToken;
import languageServerProtocol.Types.DefinitionLink;
import tokentree.TokenTree;

class MissingArgumentsAction {
	public static function createMissingArgumentsAction(context:Context, action:CodeAction, params:CodeActionParams,
			diagnostic:Diagnostic):Null<Promise<CodeAction>> {
		if ((params.context.only != null) && (!params.context.only.contains(QuickFix))) {
			return null;
		}
		final document = context.documents.getHaxe(params.textDocument.uri);
		if (document == null)
			return null;
		var fileName:String = document.uri.toFsPath().toString();
		final pos = document.offsetAt(diagnostic.range.end) - 1;
		var tokenSource = new CancellationTokenSource();

		final argToken = document.tokens!.getTokenAtOffset(document.offsetAt(diagnostic.range.start));
		if (argToken == null)
			return null;
		final funPos = getCallNamePos(document, argToken);
		if (funPos == null)
			return null;
		final gotoPromise = new Promise(function(resolve:(hover:Array<DefinitionLink>) -> Void, reject) {
			context.gotoDefinition.onGotoDefinition({
				textDocument: params.textDocument,
				position: funPos.start
			}, tokenSource.token, array -> {
				resolve(array);
			}, error -> reject(error));
		});
		final hoverPromise = makeHoverRequest(context, fileName, pos, tokenSource.token);

		final actionPromise = Promise.all([gotoPromise, hoverPromise]).then(results -> {
			final definitions:Array<DefinitionLink> = results[0];
			// TODO investigate multiple definitions case
			final definition = definitions[0] ?? return action;
			final hover:HoverDisplayItemOccurence<Dynamic> = results[1];
			final printer = new DisplayPrinter(true, Qualified, {
				argumentTypeHints: true,
				returnTypeHint: Always,
				useArrowSyntax: true,
				placeOpenBraceOnNewLine: false,
				explicitPublic: true,
				explicitPrivate: true,
				explicitNull: true
			});
			final item = hover.item;
			final itemType = item.type;
			if (itemType == null)
				return action;
			final type = itemType.removeNulls().type;
			var typeHint = printer.printType(type);
			typeHint = ~/Null<Null<(.+?)>>/g.replace(typeHint, "Null<$1>");
			final definitionDoc = context.documents.getHaxe(definition.targetUri);
			if (definitionDoc == null)
				return action;
			final definitonFunToken = definitionDoc.tokens!.getTokenAtOffset(definitionDoc.offsetAt(definition.targetSelectionRange.start));
			final argRange = functionNewArgPos(definitionDoc, definitonFunToken) ?? return action;
			final hadCommaAtEnd = functionArgsEndsWithComma(definitionDoc, definitonFunToken);
			var argName = generateArgName(item);
			final argNames = getArgsNames(context, definitionDoc, definitonFunToken);
			for (i in 1...10) {
				final name = argName + (i == 1 ? "" : '$i');
				if (!argNames.contains(name)) {
					argName = name;
					break;
				}
			}
			final isSnippet = context.hasClientCommandSupport("haxe.codeAction.insertSnippet");
			var arg = '$argName';
			if (isSnippet)
				arg = '$${1:$arg}';
			if (typeHint != "?")
				arg += ':$typeHint';
			if (functionArgsCount(definitionDoc, definitonFunToken) > 0) {
				arg = hadCommaAtEnd ? ' $arg' : ', $arg';
			}
			if (isSnippet) {
				action.command = {
					title: "Insert Snippet",
					command: "haxe.codeAction.insertSnippet",
					arguments: [definitionDoc.uri.toString(), argRange, arg]
				}
			} else {
				action.edit = WorkspaceEditHelper.create(definitionDoc, [{range: argRange, newText: arg}]);
				action.command = {
					title: "Highlight Insertion",
					command: "haxe.codeAction.highlightInsertion",
					arguments: [definitionDoc.uri.toString(), argRange]
				}
			}
			return action;
		});
		return actionPromise;
	}

	static function generateArgName(item:DisplayItem<Dynamic>):String {
		switch item.kind {
			case Literal:
			case AnonymousStructure:
				return "obj";
			case ClassField:
				return item.args!.field!.name ?? "arg";
			case Expression:
				if (item.type!.kind == TFun)
					return "callback";
			case _:
				return item.args!.name ?? "arg";
		}
		return genArgNameFromJsonType(item.type);
	}

	public static function genArgNameFromJsonType(type:Null<JsonType<Dynamic>>):String {
		final dotPath = type!.getDotPath() ?? return "arg";
		return switch dotPath {
			case Std_Bool: "bool";
			case Std_Int, Std_UInt: "i";
			case Std_Float: "f";
			case Std_String: "s";
			case Std_Array, Haxe_Ds_ReadOnlyArray: "arr";
			case Std_EReg: "regExp";
			case Std_Dynamic: "value";
			case Haxe_Ds_Map: "map";
			case _: "arg";
		}
	}

	static function getArgsNames(context:Context, document:HaxeDocument, funIdent:Null<TokenTree>):Array<String> {
		final pOpen = getFunctionPOpen(funIdent) ?? return [];
		final args = pOpen.filterCallback((tree, depth) -> {
			if (depth == 0)
				GoDeeper;
			else
				tree.isCIdent() ? FoundSkipSubtree : SkipSubtree;
		});
		return args.map(tree -> tree.toString());
	}

	static function makeHoverRequest<T>(context:Context, fileName:String, pos:Int, token:CancellationToken):Promise<Null<HoverDisplayItemOccurence<T>>> {
		var request:HoverRequestContext<T> = {
			params: cast {
				file: cast fileName,
				offset: pos
			},
			token: token,
			resolve: null
		}
		var promise = new Promise(function(resolve:(hover:Null<HoverDisplayItemOccurence<T>>) -> Void, reject) {
			request.resolve = resolve;
		});
		context.callHaxeMethod(DisplayMethods.Hover, request.params, request.token, function(hover) {
			if (request.resolve != null) {
				if (hover == null) {
					request.resolve(null);
				} else {
					request.resolve(hover);
				}
			}
			return null;
		}, function(msg) {
			if (request.resolve != null) {
				request.resolve(null);
			}
			return;
		});
		return promise;
	}

	static function getCallNamePos(document:HaxeDocument, argToken:TokenTree):Null<Range> {
		final parent = argToken.access().findParent(helper -> {
			return switch (helper!.token!.tok) {
				case Const(CIdent(_)): true;
				case _: false;
			}
		});
		if (parent == null) {
			return null;
		}
		final tokenPos = parent.token.pos;
		return document.rangeAt(tokenPos.min, tokenPos.max, Utf8);
	}

	static function getFunctionPOpen(funIdent:Null<TokenTree>):Null<TokenTree> {
		if (funIdent == null)
			return null;
		// Check for: var foo:()->Void = ...
		final isFunction = switch (funIdent!.parent!.tok) {
			case Kwd(KwdFunction): true;
			case _: false;
		}
		if (!isFunction) {
			funIdent = funIdent.getFirstChild() ?? return null;
		}
		final pOpen = funIdent.access().firstOf(POpen)!.token;
		return pOpen;
	}

	static function functionNewArgPos(document:HaxeDocument, funIdent:Null<TokenTree>):Null<Range> {
		final pOpen = getFunctionPOpen(funIdent);
		if (pOpen == null) {
			return null;
		}
		final pClose = pOpen.access().firstOf(PClose)!.token;
		if (pClose == null) {
			return null;
		}
		return document.rangeAt(pClose.pos.min, pClose.pos.min, Utf8);
	}

	static function functionArgsCount(document:HaxeDocument, funIdent:Null<TokenTree>):Int {
		final pOpen = getFunctionPOpen(funIdent) ?? return 0;
		final args = pOpen.filterCallback((tree, depth) -> {
			if (depth == 0)
				GoDeeper;
			else
				tree.isCIdent() ? FoundSkipSubtree : SkipSubtree;
		});
		return args.length;
	}

	static function functionArgsEndsWithComma(document:HaxeDocument, funIdent:Null<TokenTree>):Bool {
		final pOpen = getFunctionPOpen(funIdent) ?? return false;
		final maybeComma = pOpen.getLastChild()!.getLastChild();
		if (maybeComma == null) {
			return false;
		}
		return maybeComma.matches(Comma);
	}
}

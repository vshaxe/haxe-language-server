package haxeLanguageServer.features.haxe;

import haxe.display.Display;
import haxeLanguageServer.protocol.DisplayPrinter;
import js.lib.Promise;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.InlayHint;
import languageServerProtocol.protocol.InlayHints;
import tokentree.TokenTree;
import tokentree.utils.TokenTreeCheckUtils;

using tokentree.TokenTreeAccessHelper;

class InlayHintFeature {
	final context:Context;
	final converter:Haxe3DisplayOffsetConverter;
	final printer:DisplayPrinter;
	final cache:InlayHintCache;
	final hoverRequests:Array<HoverRequestContext<Any>> = [];

	var inlayHintsVariableTypes:Bool = false;
	var inlayHintsParameterNames:Bool = false;
	var inlayHintsParameterTypes:Bool = false;
	var inlayHintsFunctionReturnTypes:Bool = false;
	var inlayHintsConditionls:Bool = false;

	public function new(context:Context) {
		this.context = context;

		cache = new InlayHintCache();
		converter = new Haxe3DisplayOffsetConverter();
		printer = new DisplayPrinter(true, Qualified, {
			argumentTypeHints: true,
			returnTypeHint: NonVoid,
			useArrowSyntax: false,
			placeOpenBraceOnNewLine: false,
			explicitPublic: true,
			explicitPrivate: true,
			explicitNull: true
		});

		context.languageServerProtocol.onRequest(InlayHintRequest.type, onInlayHint);
	}

	function onInlayHint(params:InlayHintParams, token:CancellationToken, resolve:Array<InlayHint>->Void, reject:ResponseError<NoData>->Void) {
		final onResolve:(?result:Null<Dynamic>, ?debugInfo:Null<String>) -> Void = context.startTimer("textDocument/inlayHint");
		final uri = params.textDocument.uri;
		final doc = context.documents.getHaxe(uri);
		if (doc == null) {
			return reject.noFittingDocument(uri);
		}
		var fileName:String = uri.toFsPath().toString();
		registerChangeHandler(doc, fileName);

		var startPos = doc.offsetAt(params.range.start);
		var endPos = doc.offsetAt(params.range.end);

		var inlayHints:Array<InlayHint> = [];
		var root:Null<TokenTree> = doc?.tokens?.tree;
		if (root == null) {
			return reject.noFittingDocument(uri);
		}
		#if debug_inlayhints
		trace('[inlayHints] requesting inlay hints for $fileName lines ${params.range.start.line}-${params.range.end.line}');
		#end
		removeCancelledRequests();

		inlayHintsVariableTypes = context.config.user?.inlayHints?.variableTypes ?? false;
		inlayHintsParameterNames = context.config.user?.inlayHints?.parameterNames ?? false;
		inlayHintsParameterTypes = context.config.user?.inlayHints?.parameterTypes ?? false;
		inlayHintsFunctionReturnTypes = context.config.user?.inlayHints?.functionReturnTypes ?? false;
		inlayHintsConditionls = context.config.user?.inlayHints?.conditionals ?? false;

		if (!inlayHintsVariableTypes && !inlayHintsParameterNames && !inlayHintsParameterTypes && !inlayHintsFunctionReturnTypes && !inlayHintsConditionls) {
			resolve([]);
			onResolve(null, "disabled");
			return;
		}

		var promises:PromisedInlayHintResults = [];
		if (inlayHintsVariableTypes) {
			promises = promises.concat(findAllVars(doc, fileName, root, startPos, endPos, token));
		}
		if (inlayHintsParameterNames || inlayHintsFunctionReturnTypes || inlayHintsParameterTypes) {
			promises = promises.concat(findAllPOpens(doc, fileName, root, startPos, endPos, token));
		}
		if (inlayHintsConditionls) {
			promises = promises.concat(findAllConditionals(doc, fileName, root, startPos, endPos, token));
		}

		if (promises.length <= 0) {
			resolve([]);
			onResolve(null, "0 hints");
			return;
		}
		Promise.all(promises).then(function(inlayHints:Array<Array<InlayHint>>) {
			var hints:Array<InlayHint> = [];
			for (hintList in inlayHints) {
				if (hintList == null) {
					continue;
				}
				hints = hints.concat(hintList);
			}
			resolve(hints);
			onResolve(null, hints.length + " hints");
		}).catchError(function(_) {
			return Promise.resolve();
		});
	}

	function findAllConditionals(doc:HaxeDocument, fileName:String, root:TokenTree, startPos:Int, endPos:Int,
			token:CancellationToken):PromisedInlayHintResults {
		var promises:PromisedInlayHintResults = [];
		var allConditionals:Array<TokenTree> = root.filterCallback(function(token:TokenTree, _) {
			if (startPos > token.pos.min) {
				return GoDeeper;
			}
			if (endPos < token.pos.min) {
				return GoDeeper;
			}
			return switch (token.tok) {
				case Sharp("end"):
					FoundSkipSubtree;
				default:
					GoDeeper;
			}
		});
		for (c in allConditionals) {
			var parent = c.parent;
			while (parent != null) {
				switch (parent.tok) {
					case Sharp("if"):
						break;
					default:
						parent = parent.parent;
				}
			}
			if (parent == null) {
				continue;
			}

			var conditionToken:Null<TokenTree> = parent.getFirstChild();
			if (conditionToken == null) {
				continue;
			}
			var pos = conditionToken.getPos();
			var conditionStart = converter.byteOffsetToCharacterOffset(doc.content, pos.min);
			var conditionEnd = converter.byteOffsetToCharacterOffset(doc.content, pos.max);
			var text = " // " + doc.content.substring(conditionStart, conditionEnd);

			var insertPos = converter.byteOffsetToCharacterOffset(doc.content, c.pos.max);
			var indexOfText = doc.content.indexOf(text, insertPos);
			if (indexOfText - insertPos >= 0 && indexOfText - insertPos < 5) {
				continue;
			}

			var hint:InlayHint = {
				position: doc.positionAt(insertPos),
				label: text,
				kind: Type,
				textEdits: [
					{
						range: doc.rangeAt(insertPos, insertPos),
						newText: text
					}
				],
				paddingRight: false,
				paddingLeft: true
			};
			if (hint == null) {
				continue;
			}
			promises.push(Promise.resolve(cast [hint]));
		}
		return promises;
	}

	function findAllVars(doc:HaxeDocument, fileName:String, root:TokenTree, startPos:Int, endPos:Int, token:CancellationToken):PromisedInlayHintResults {
		var promises:PromisedInlayHintResults = [];
		var allVars:Array<TokenTree> = root.filterCallback(function(token:TokenTree, _) {
			if (startPos > token.pos.min) {
				return GoDeeper;
			}
			if (endPos < token.pos.min) {
				return GoDeeper;
			}
			return switch (token.tok) {
				case Kwd(KwdVar):
					FoundGoDeeper;
				case Kwd(KwdFinal):
					if (!token.hasChildren()) {
						return SkipSubtree;
					}
					FoundSkipSubtree;
				default:
					GoDeeper;
			}
		});
		for (v in allVars) {
			var nameToken:Null<TokenTree> = v.getFirstChild();
			if (nameToken == null) {
				continue;
			}
			switch (nameToken.tok) {
				case Question:
					nameToken = nameToken.getFirstChild();
				default:
			}
			if (nameToken == null) {
				continue;
			}
			if (nameToken.access().firstOf(DblDot).exists()) {
				continue;
			}
			var insertPos = nameToken.pos.max;
			var childs = nameToken.children;
			if (childs != null) {
				for (child in childs) {
					switch (child.tok) {
						case At:
						case POpen:
							var pos = child.getPos();
							insertPos = pos.max;
						default:
							break;
					}
				}
			}
			var hint = hintFromCache(fileName, nameToken.index, nameToken.pos.min);
			if (hint != null) {
				promises.push(cast Promise.resolve([hint]));
				continue;
			}
			var pos = converter.byteOffsetToCharacterOffset(doc.content, nameToken.pos.min);
			promises.push(resolveType(fileName, pos, token).then(function(hover) {
				if (hover == null) {
					return Promise.resolve();
				}
				var hint = makeTypeHint(doc, hover, insertPos, buildTypeHint);
				if (hint == null) {
					return Promise.resolve();
				}
				cacheHint(fileName, nameToken.index, nameToken.pos.min, hint);
				return Promise.resolve(cast [hint]);
			}).catchError(function(_) {
				return Promise.resolve();
			}));
		}
		return promises;
	}

	function findAllPOpens(doc:HaxeDocument, fileName:String, root:TokenTree, startPos:Int, endPos:Int, token:CancellationToken):PromisedInlayHintResults {
		var promises:PromisedInlayHintResults = [];
		var allPOpens:Array<TokenTree> = root.filterCallback(function(token:TokenTree, _) {
			if (startPos > token.pos.min) {
				return GoDeeper;
			}
			if (endPos < token.pos.min) {
				return GoDeeper;
			}
			return switch (token.tok) {
				case POpen:
					FoundGoDeeper;
				default:
					GoDeeper;
			}
		});
		for (pOpen in allPOpens) {
			switch (TokenTreeCheckUtils.getPOpenType(pOpen)) {
				case At | SwitchCondition | WhileCondition | IfCondition | SharpCondition | Catch | ForLoop | Expression:
				case Parameter:
					if (inlayHintsFunctionReturnTypes) {
						promises = promises.concat(makeFunctionInlayHints(doc, fileName, pOpen, token));
					}
				case Call:
					if (inlayHintsParameterNames || inlayHintsParameterTypes) {
						promises = promises.concat(makeCallInlayHints(doc, fileName, pOpen, token));
					}
			}
		}
		return promises;
	}

	function makeFunctionInlayHints(doc:HaxeDocument, fileName:String, pOpen:TokenTree, token:CancellationToken):PromisedInlayHintResults {
		var promises:PromisedInlayHintResults = [];

		if (pOpen.access().parent().firstOf(DblDot).exists()) {
			return promises;
		}
		if (pOpen.access().parent().matches(Kwd(KwdNew)).exists()) {
			return promises;
		}
		var pClose:Null<TokenTree> = pOpen.access().firstOf(PClose)?.token;
		if (pClose == null) {
			return promises;
		}

		var hint = hintFromCache(fileName, pOpen.index, pOpen.pos.min);
		if (hint != null) {
			promises.push(cast Promise.resolve([hint]));
			return promises;
		}

		var insertPos = pClose.pos.max;
		var pos = converter.byteOffsetToCharacterOffset(doc.content, pOpen.pos.min);
		promises.push(resolveType(fileName, pos, token).then(function(hover) {
			if (hover == null) {
				return Promise.resolve();
			}
			var hint = makeTypeHint(doc, hover, insertPos, buildReturnTypeHint);
			if (hint == null) {
				return Promise.resolve();
			}
			cacheHint(fileName, pOpen.index, pOpen.pos.min, hint);
			return Promise.resolve(cast [hint]);
		}).catchError(function(_) {
			return Promise.resolve();
		}));

		return promises;
	}

	function makeTypeHint<T>(doc:HaxeDocument, hover:HoverDisplayItemOccurence<T>, insertPos:Int, printFunc:TypePrintFunc<T>):Null<InlayHint> {
		var type = printFunc(hover);
		if (type == null) {
			return null;
		}
		var text = ':$type';
		var hint:InlayHint = {
			position: doc.positionAt(converter.byteOffsetToCharacterOffset(doc.content, insertPos)),
			label: text,
			kind: Type,
			textEdits: [
				{
					range: doc.rangeAt(insertPos, insertPos),
					newText: text
				}
			],
			paddingRight: false,
			paddingLeft: true
		};
		return hint;
	}

	function makeCallInlayHints(doc:HaxeDocument, fileName:String, pOpen:TokenTree, token:CancellationToken):PromisedInlayHintResults {
		var promises:PromisedInlayHintResults = [];

		var pClose:Null<TokenTree> = pOpen.access().firstOf(PClose).token;
		if (pClose == null) {
			return promises;
		}
		if (pClose.pos.min == pOpen.pos.max) {
			return promises;
		}
		var childs = pOpen.children;
		if (childs == null) {
			return promises;
		}
		for (paramChild in childs) {
			switch (paramChild.tok) {
				case PClose:
					return promises;
				case Const(CIdent("_")):
					continue;
				case Binop(_):
					continue;
				default:
			}
			var insertPos:Int = paramChild.pos.min;
			var typeInsertPos = findParamTypePos(paramChild);
			var hoverTarget = findHoverTarget(paramChild);

			var cachedHints:Array<InlayHint> = [];
			if (inlayHintsParameterNames) {
				var hint = hintFromCache(fileName, hoverTarget.index, hoverTarget.pos.min);
				if (hint != null) {
					cachedHints.push(hint);
				}
			}
			if (inlayHintsParameterTypes) {
				var hint = hintFromCache(fileName, hoverTarget.index, typeInsertPos);
				if (hint != null) {
					cachedHints.push(hint);
				}
			}
			if (cachedHints.length > 0) {
				promises.push(Promise.resolve(cachedHints));
				continue;
			}

			var pos = converter.byteOffsetToCharacterOffset(doc.content, hoverTarget.pos.min);
			promises.push(resolveType(fileName, pos, token).then(function(hover) {
				if (hover == null) {
					return Promise.resolve();
				}
				var hints:Array<InlayHint> = [];
				if (inlayHintsParameterNames) {
					var name = buildParameterName(hover);
					if (name == null) {
						return Promise.resolve();
					}
					if (name == "") {
						name = "<unnamed>";
					}
					var text = '$name:';
					var nameHint:InlayHint = {
						position: doc.positionAt(converter.byteOffsetToCharacterOffset(doc.content, insertPos)),
						label: text,
						kind: Parameter,
						paddingRight: true,
						paddingLeft: false
					};
					cacheHint(fileName, hoverTarget.index, hoverTarget.pos.min, nameHint);
					hints.push(nameHint);
				}

				if (inlayHintsParameterTypes) {
					var type = buildTypeHint(hover);
					if (type == null) {
						return Promise.resolve(hints);
					}
					if (type != "") {
						var text = ' /* $type */';
						var typeHint:InlayHint = {
							position: doc.positionAt(converter.byteOffsetToCharacterOffset(doc.content, typeInsertPos)),
							label: text,
							kind: Type,
							paddingRight: false,
							paddingLeft: true
						};
						cacheHint(fileName, hoverTarget.index, typeInsertPos, typeHint);
						hints.push(typeHint);
					}
				}
				return Promise.resolve(hints);
			}).catchError(function(_) {
				return Promise.resolve();
			}));
		}

		return promises;
	}

	function findHoverTarget(token:TokenTree):TokenTree {
		var lastBinop:Null<TokenTree> = null;
		while (token.nextSibling != null) {
			switch (token.nextSibling.tok) {
				case Binop(_):
					token = token.nextSibling;
					lastBinop = token;
				default:
					break;
			}
		}
		if (lastBinop != null) {
			return lastBinop;
		}
		if (!token.hasChildren()) {
			return token;
		}
		switch (token.tok) {
			case Kwd(KwdThis):
			case Kwd(_) | Comma | BrOpen:
				return token;
			default:
		}
		var lastChild = token.getLastChild();
		if (lastChild == null) {
			return token;
		}
		switch (lastChild.tok) {
			case Comma:
				lastChild = lastChild.previousSibling;
				if (lastChild == null) {
					return token;
				}
				return findHoverTarget(lastChild);
			default:
				return findHoverTarget(lastChild);
		}
	}

	function findParamTypePos(token:TokenTree):Int {
		var lastChild = token.getLastChild();
		if (lastChild == null) {
			return token.pos.max;
		}
		if (lastChild.tok.match(Comma)) {
			if (lastChild.previousSibling == null) {
				return token.pos.max;
			}
			lastChild = lastChild.previousSibling;
		}
		if (lastChild == null) {
			return token.pos.max;
		}
		return lastChild.getPos().max;
	}

	public function resolveType<T>(fileName:String, pos:Int, token:CancellationToken):Promise<Null<HoverDisplayItemOccurence<T>>> {
		var newRequest:HoverRequestContext<T> = {
			params: cast {
				file: cast fileName,
				offset: pos
			},
			token: token,
			resolve: null
		}
		var promise = new Promise(function(resolve:(hover:Null<HoverDisplayItemOccurence<T>>) -> Void, reject) {
			newRequest.resolve = resolve;
		});
		hoverRequests.push(newRequest);
		if (hoverRequests.length != 1) {
			return promise;
		}
		requestHover(newRequest);
		return promise;
	}

	function requestHover<T>(request:HoverRequestContext<T>) {
		if (request.token.canceled) {
			hoverRequests.shift();
			nextHover();
			return;
		}

		context.callHaxeMethod(DisplayMethods.Hover, request.params, request.token, function(hover) {
			if (request.resolve != null) {
				if (hover == null) {
					request.resolve(null);
				} else {
					request.resolve(hover);
				}
			}
			hoverRequests.shift();
			nextHover();
			return null;
		}, function(msg) {
			if (request.resolve != null) {
				request.resolve(null);
			}
			hoverRequests.shift();
			nextHover();
			return;
		});
	}

	function nextHover() {
		if (hoverRequests.length <= 0) {
			return;
		}
		requestHover(hoverRequests[0]);
	}

	function removeCancelledRequests() {
		while (hoverRequests.length > 0) {
			if (!hoverRequests[0].token.canceled) {
				return;
			}
			hoverRequests.shift();
		}
	}

	function buildParameterName<T>(hover:HoverDisplayItemOccurence<T>):Null<String> {
		return hover.expected?.name?.name;
	}

	function buildTypeHint<T>(hover:HoverDisplayItemOccurence<T>):Null<String> {
		var type = hover.item?.type;
		if (type == null) {
			return null;
		}
		return printer.printType(type);
	}

	function buildReturnTypeHint<T>(hover:HoverDisplayItemOccurence<T>):Null<String> {
		var type = hover.item.type?.args?.ret;
		if (type == null) {
			return null;
		}
		return printer.printType(type);
	}

	function registerChangeHandler(doc:HaxeDocument, fileName:String) {
		if (cache.exists(fileName)) {
			return;
		}
		doc.removeUpdateListener(onDocChange);
		doc.addUpdateListener(onDocChange);
	}

	function onDocChange(doc:HxTextDocument, changes:Array<TextDocumentContentChangeEvent>, version:Int) {
		var fileName:String = doc.uri.toFsPath().toString();
		cache.remove(fileName);
	}

	function hintFromCache(fileName:String, tokenIndex:Int, position:Int):Null<InlayHint> {
		var fileCache = cache.get(fileName);
		if (fileCache == null) {
			return null;
		}

		// somehow faster than `return fileCache.get('$position.$tokenIndex');`?
		var key = '$position.$tokenIndex';
		var hint = fileCache.get(key);
		return hint;
	}

	function cacheHint(fileName:String, tokenIndex:Int, position:Int, hint:InlayHint) {
		var fileCache = cache.get(fileName);
		if (fileCache == null) {
			fileCache = new Map<String, InlayHint>();
			cache.set(fileName, fileCache);
		}
		var key = '$position.$tokenIndex';
		fileCache.set(key, hint);
	}
}

typedef TypePrintFunc<T> = (hover:HoverDisplayItemOccurence<T>) -> Null<String>;
typedef InlayHintCache = Map<String, Map<String, InlayHint>>;
typedef PromisedInlayHintResults = Array<Promise<Array<InlayHint>>>;

typedef HoverRequestContext<T> = {
	var params:PositionParams;
	var token:CancellationToken;
	var ?resolve:(hover:Null<HoverDisplayItemOccurence<T>>) -> Void;
}

package haxeLanguageServer.features.haxe;

import haxe.display.Display;
import haxeLanguageServer.protocol.DisplayPrinter;
import js.lib.Promise;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
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
		var root:Null<TokenTree> = doc!.tokens!.tree;
		if (root == null) {
			return reject.noFittingDocument(uri);
		}
		#if debug
		trace('[inlayHints] requesting inlay hints for $fileName lines ${params.range.start.line}-${params.range.end.line}');
		#end
		removeCancelledRequests();

		var promises:Array<Promise<InlayHint>> = [];
		promises = promises.concat(findAllVars(doc, fileName, root, startPos, endPos, token));
		promises = promises.concat(findAllPOpens(doc, fileName, root, startPos, endPos, token));

		Promise.all(promises).then(function(inlayHints:Array<InlayHint>) {
			var hints:Array<InlayHint> = [];
			for (hint in inlayHints) {
				if (hint == null) {
					continue;
				}
				hints.push(hint);
			}
			resolve(hints);
			onResolve(null, hints.length + " hints");
		}).catchError(function(_) {
			return Promise.resolve();
		});
	}

	function findAllVars(doc:HaxeDocument, fileName:String, root:TokenTree, startPos:Int, endPos:Int, token:CancellationToken):Array<Promise<InlayHint>> {
		var promises:Array<Promise<InlayHint>> = [];
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
			if (nameToken.hasChildren()) {
				@:nullSafety(Off)
				for (child in nameToken.children) {
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
				promises.push(Promise.resolve(hint));
				continue;
			}
			var pos = converter.byteOffsetToCharacterOffset(doc.content, nameToken.pos.min);
			promises.push(resolveType(fileName, pos, buildTypeHint, token).then(function(type) {
				if (type == null) {
					return Promise.resolve();
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
				cacheHint(fileName, nameToken.index, nameToken.pos.min, hint);
				return Promise.resolve(hint);
			}).catchError(function(_) {
				return Promise.resolve();
			}));
		}
		return promises;
	}

	function findAllPOpens(doc:HaxeDocument, fileName:String, root:TokenTree, startPos:Int, endPos:Int, token:CancellationToken):Array<Promise<InlayHint>> {
		var promises:Array<Promise<InlayHint>> = [];
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
					promises = promises.concat(makeFunctionInlayHints(doc, fileName, pOpen, token));
				case Call:
					promises = promises.concat(makeCallInlayHints(doc, fileName, pOpen, token));
			}
		}
		return promises;
	}

	function makeFunctionInlayHints(doc:HaxeDocument, fileName:String, pOpen:TokenTree, token:CancellationToken):Array<Promise<InlayHint>> {
		var promises:Array<Promise<InlayHint>> = [];

		if (pOpen.access().parent().firstOf(DblDot).exists()) {
			return promises;
		}
		if (pOpen.access().parent().matches(Kwd(KwdNew)).exists()) {
			return promises;
		}
		var pClose:Null<TokenTree> = pOpen.access().firstOf(PClose).token;
		if (pClose == null) {
			return promises;
		}

		var hint = hintFromCache(fileName, pOpen.index, pOpen.pos.min);
		if (hint != null) {
			promises.push(Promise.resolve(hint));
			return promises;
		}

		var insertPos = pClose.pos.max;
		var pos = converter.byteOffsetToCharacterOffset(doc.content, pOpen.pos.min);
		promises.push(resolveType(fileName, pos, buildReturnTypeHint, token).then(function(type) {
			if (type == null) {
				return Promise.resolve();
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
			cacheHint(fileName, pOpen.index, pOpen.pos.min, hint);
			return Promise.resolve(hint);
		}).catchError(function(_) {
			return Promise.resolve();
		}));

		return promises;
	}

	function makeCallInlayHints(doc:HaxeDocument, fileName:String, pOpen:TokenTree, token:CancellationToken):Array<Promise<InlayHint>> {
		var promises:Array<Promise<InlayHint>> = [];

		var pClose:Null<TokenTree> = pOpen.access().firstOf(PClose).token;
		if (pClose == null) {
			return promises;
		}
		if (pClose.pos.min == pOpen.pos.max) {
			return promises;
		}
		@:nullSafety(Off)
		for (paramChild in pOpen.children) {
			switch (paramChild.tok) {
				case PClose:
					return promises;
				case Const(CIdent("_")):
					continue;
				case Binop(_):
					continue;
				default:
			}
			var insertPos = paramChild.pos.min;
			var hoverTarget = findHoverTarget(paramChild);

			var hint = hintFromCache(fileName, hoverTarget.index, hoverTarget.pos.min);
			if (hint != null) {
				promises.push(Promise.resolve(hint));
				continue;
			}

			var pos = converter.byteOffsetToCharacterOffset(doc.content, hoverTarget.pos.min);
			promises.push(resolveType(fileName, pos, buildParameterName, token).then(function(type) {
				if (type == null) {
					return Promise.resolve();
				}
				if (type == "") {
					type = "<unnamed>";
				}
				var text = '$type:';
				var hint:InlayHint = {
					position: doc.positionAt(converter.byteOffsetToCharacterOffset(doc.content, insertPos)),
					label: text,
					kind: Parameter,
					paddingRight: true,
					paddingLeft: false
				};
				cacheHint(fileName, hoverTarget.index, hoverTarget.pos.min, hint);
				return Promise.resolve(hint);
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

	public function resolveType<T>(fileName:String, pos:Int, printFunc:TypePrintFunc<T>, token:CancellationToken):Promise<Null<String>> {
		var newRequest:HoverRequestContext<T> = {
			params: cast {
				file: cast fileName,
				offset: pos
			},
			printFunc: printFunc,
			token: token,
			resolve: null
		}
		var promise = new Promise(function(resolve:(value:Null<String>) -> Void, reject) {
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
					request.resolve(request.printFunc(hover));
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
		return hover.expected!.name!.name;
	}

	function buildTypeHint<T>(hover:HoverDisplayItemOccurence<T>):Null<String> {
		var type = hover.item!.type;
		if (type == null) {
			return null;
		}
		return printer.printType(type);
	}

	function buildReturnTypeHint<T>(hover:HoverDisplayItemOccurence<T>):Null<String> {
		var type = hover.item.type!.args!.ret;
		if (type == null) {
			return null;
		}
		return printer.printType(type);
	}

	function registerChangeHandler(doc:HaxeDocument, fileName:String) {
		if (cache.exists(fileName)) {
			return;
		}
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

typedef HoverRequestContext<T> = {
	var params:PositionParams;
	var printFunc:TypePrintFunc<T>;
	var token:CancellationToken;
	var ?resolve:(value:Null<String>) -> Void;
}

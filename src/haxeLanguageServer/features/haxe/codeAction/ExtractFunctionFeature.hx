package haxeLanguageServer.features.haxe.codeAction;

import haxeLanguageServer.helper.FormatterHelper;
import haxeLanguageServer.helper.WorkspaceEditHelper;
import tokentree.TokenTree;
import tokentree.TokenTreeBuilder;
import tokentree.utils.TokenTreeCheckUtils;

using tokentree.TokenTreeAccessHelper;

class ExtractFunctionFeature {
	final context:Context;

	public function new(context:Context) {
		this.context = context;
		#if debug
		context.registerCodeActionContributor(extractFunction);
		#end
	}

	function extractFunction(params:CodeActionParams):Array<CodeAction> {
		final doc = context.documents.getHaxe(params.textDocument.uri);
		if (doc == null) {
			return [];
		}
		final tokens = doc.tokens;
		if (tokens == null) {
			return [];
		}
		return try {
			var text:String = doc.getText(params.range);
			final leftOffset:Int = text.length - text.ltrim().length;
			final rightOffset:Int = text.length - text.rtrim().length;
			text = text.trim();

			final tokenStart:Null<TokenTree> = tokens.getTokenAtOffset(doc.offsetAt(params.range.start) + leftOffset);
			final tokenEnd:Null<TokenTree> = tokens.getTokenAtOffset(doc.offsetAt(params.range.end) - rightOffset);
			if (tokenStart == null || tokenEnd == null)
				return [];
			if (tokenStart.index == tokenEnd.index)
				return [];
			// TODO is a minimum of 10 tokens between start and end enough / too much? is there a better solution
			if (tokenStart.index + 10 > tokenEnd.index)
				return [];

			final parentOfStart:Null<TokenTree> = findParentFunction(tokenStart);
			final parentOfEnd:Null<TokenTree> = findParentFunction(tokenEnd);
			if (parentOfStart == null || parentOfEnd == null)
				return [];
			if (parentOfStart.index != parentOfEnd.index)
				return [];
			final lastToken:Null<TokenTree> = TokenTreeCheckUtils.getLastToken(parentOfStart);

			final rangeIdents:Array<String> = [];
			final varTokens:Array<TokenTree> = [];
			var hasReturn:Bool = false;
			parentOfStart.filterCallback(function(token:TokenTree, index:Int):FilterResult {
				if (lastToken == null || token.index > lastToken.index)
					return SKIP_SUBTREE;
				switch (token.tok) {
					case Const(CIdent(s)):
						if ((token.index >= tokenStart.index) && (token.index <= tokenEnd.index) && (!rangeIdents.contains(s)))
							rangeIdents.push(s);
					case Dollar(s):
						if ((token.index >= tokenStart.index) && (token.index <= tokenEnd.index) && (!rangeIdents.contains(s)))
							rangeIdents.push("$" + s);
					case Kwd(KwdReturn):
						if ((token.index >= tokenStart.index) && (token.index <= tokenEnd.index))
							hasReturn = true;
					case Kwd(KwdVar):
						if (token.index >= tokenStart.index)
							return GO_DEEPER;
						if ((token.index >= parentOfStart.index) && (token.index <= lastToken.index))
							varTokens.push(token);
					default:
				}
				return GO_DEEPER;
			});

			var returnSpec:String = "";
			if (hasReturn) {
				returnSpec = makeReturnSpec(parentOfStart);
			}
			final isStatic:Bool = isStaticFunction(parentOfStart);
			final indent:String = detectIndent(doc, parentOfStart);

			var newParams:Array<NewFunctionParameter> = copyParentFunctionParameters(parentOfStart, text, rangeIdents);
			newParams = newParams.concat(localVarsToParameter(varTokens, text, rangeIdents));

			final action:Null<CodeAction> = makeExtractFunctionChanges(doc, doc.uri, params, text, isStatic, newParams, returnSpec, indent,
				doc.positionAt(lastToken.pos.max + 1));
			if (action == null)
				return [];
			[action];
		} catch (e) {
			[];
		}
	}

	function makeExtractFunctionChanges(doc:HaxeDocument, uri:DocumentUri, params:CodeActionParams, text:String, isStatic:Bool,
			newParams:Array<NewFunctionParameter>, returnSpec:String, indent:String, newFuncPos:Position):CodeAction {
		final callParams:String = newParams.map(s -> s.call).join(", ");
		final funcParams:String = newParams.map(s -> s.param).join(", ");

		final funcName:String = "newFunction";

		var call:String = '$funcName($callParams);\n';
		if (returnSpec.length > 0) {
			call = 'return $call';
		}

		var func:String = 'function $funcName($funcParams)$returnSpec {\n$text\n}\n';
		if (isStatic) {
			func = 'static $func';
		}

		call = FormatterHelper.formatText(doc, context, call, TokenTreeEntryPoint.FIELD_LEVEL);
		func = FormatterHelper.formatText(doc, context, func, TokenTreeEntryPoint.FIELD_LEVEL);
		func = func.split("\n").map(s -> indent + s).join("\n");
		final edits:Array<TextEdit> = [];

		edits.push(WorkspaceEditHelper.insertText(newFuncPos, func));
		edits.push(WorkspaceEditHelper.replaceText(params.range, call));

		final textEdit:TextDocumentEdit = WorkspaceEditHelper.textDocumentEdit(uri, edits);
		final edit:WorkspaceEdit = {
			documentChanges: [textEdit]
		};
		return {
			title: "Extract function",
			kind: RefactorExtract,
			edit: edit
		}
	}

	function findParentFunction(token:TokenTree):Null<TokenTree> {
		var parent:Null<TokenTree> = token.parent;
		while (parent != null && parent.tok != null) {
			switch (parent.tok) {
				case Kwd(KwdFunction):
					return parent;
				default:
			}
			parent = parent.parent;
		}
		return null;
	}

	function makeReturnSpec(functionToken:TokenTree):String {
		var returnHint:Null<TokenTree> = functionToken.access().firstChild().isCIdent().firstOf(DblDot).token;
		// anon function
		if (returnHint == null)
			returnHint = functionToken.access().firstOf(DblDot).token;
		if (returnHint == null || returnHint.children == null)
			return "";
		return varToString(returnHint);
	}

	function isStaticFunction(functionToken:TokenTree):Bool {
		if (functionToken.access().firstChild().isCIdent().firstOf(Kwd(KwdStatic)).exists())
			return true;
		return false;
	}

	function detectIndent(doc:HaxeDocument, functionToken:TokenTree):String {
		final functionRange:Range = doc.rangeAt2(functionToken.pos);
		functionRange.start.character = 0;

		final text:String = doc.getText(functionRange);
		final whitespace:EReg = ~/^([ \t]+)/;
		if (!whitespace.match(text))
			return "";

		return whitespace.matched(1);
	}

	function copyParentFunctionParameters(functionToken:TokenTree, text:String, rangeIdents:Array<String>):Array<NewFunctionParameter> {
		var paramterList:Null<TokenTree> = functionToken.access().firstChild().isCIdent().firstOf(POpen).token;
		// anon function
		if (paramterList == null)
			paramterList = functionToken.access().firstOf(POpen).token;

		if (paramterList == null || paramterList.children == null)
			return [];

		final newFuncParameter:Array<NewFunctionParameter> = [];
		for (child in paramterList.children) {
			switch (child.tok) {
				case Const(CIdent(s)):
					checkAndAddIdentifier(child, s, text, rangeIdents, newFuncParameter);
				case Question:
					final firstChild:Null<TokenTree> = child.getFirstChild();
					if (firstChild == null)
						continue;
					switch (firstChild.tok) {
						case Const(CString(s)):
							checkAndAddIdentifier(child, s, text, rangeIdents, newFuncParameter);
						default:
					}
				case Dollar(s):
					if (!rangeIdents.contains("$" + s))
						continue;
					newFuncParameter.push({
						call: s,
						param: varToString(child)
					});
				case PClose:
					return newFuncParameter;
				default:
			}
		}

		return newFuncParameter;
	}

	function checkAndAddIdentifier(token:TokenTree, identifier:String, text:String, rangeIdents:Array<String>, newFuncParameter:Array<NewFunctionParameter>) {
		if (rangeIdents.contains(identifier))
			newFuncParameter.push({
				call: identifier,
				param: varToString(token)
			});
		if (text.contains("$" + identifier))
			newFuncParameter.push({
				call: identifier,
				param: varToString(token)
			});
	}

	function localVarsToParameter(varTokens:Array<TokenTree>, text:String, rangeIdents:Array<String>):Array<NewFunctionParameter> {
		final newFuncParameter:Array<NewFunctionParameter> = [];

		for (varToken in varTokens) {
			if (varToken.children == null) {
				continue;
			}
			// TODO handle multiple vars
			for (child in varToken.children) {
				switch (child.tok) {
					case Const(CIdent(s)):
						checkAndAddIdentifier(child, s, text, rangeIdents, newFuncParameter);
					case Dollar(s):
						if (!rangeIdents.contains("$" + s))
							continue;
						newFuncParameter.push({
							call: s,
							param: varToString(child)
						});
					default:
						continue;
				}
			}
		}
		return newFuncParameter;
	}

	function varToString(token:TokenTree):String {
		var result:String = token.toString();
		if (token.children == null)
			return result;
		for (child in token.children) {
			switch (child.tok) {
				case Kwd(_):
					result += varToString(child);
				case Const(_):
					result += varToString(child);
				case Dot:
					result += varToString(child);
				case DblDot:
					result += varToString(child);
				case Arrow:
					result += varToString(child);
				case Dollar(_):
					result += varToString(child);
				case Binop(OpLt):
					result += ltGtToString(child);
				default:
					return result;
			}
		}
		return result;
	}

	function ltGtToString(token:TokenTree):String {
		var result:String = token.toString();
		if (token.children == null)
			return result;
		for (child in token.children) {
			switch (child.tok) {
				case Binop(OpGt):
					result += child.toString();
					break;
				default:
					result += ltGtToString(child);
			}
		}
		return result;
	}
}

typedef NewFunctionParameter = {
	final call:String;
	final param:String;
}

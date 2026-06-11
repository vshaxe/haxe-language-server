package haxeLanguageServer.features.haxe.codeAction;

import haxeLanguageServer.features.haxe.codeAction.CodeActionFeature.CodeActionContributor;
import haxeLanguageServer.helper.FormatterHelper;
import haxeLanguageServer.helper.WorkspaceEditHelper;
import haxeLanguageServer.tokentree.TokenTreeManager;
import languageServerProtocol.Types.CodeAction;
import languageServerProtocol.Types.TextDocumentEdit;
import tokentree.TokenTree;
import tokentree.utils.TokenTreeCheckUtils;

using Lambda;
using tokentree.TokenTreeAccessHelper;

class ExtractVarFeature implements CodeActionContributor {
	final context:Context;

	public function new(context:Context) {
		this.context = context;
	}

	public function createCodeActions(params:CodeActionParams):Array<CodeAction> {
		if ((params.context.only != null) && (!params.context.only.contains(RefactorExtract))) {
			return [];
		}
		final uri = params.textDocument.uri;
		final doc = context.documents.getHaxe(uri) ?? return [];
		return extractVar(doc, uri, params.range);
	}

	function extractVar(doc:HaxeDocument, uri:DocumentUri, range:Range):Array<CodeAction> {
		final tokens = doc.tokens ?? return [];
		// only look at token at range start
		final token = tokens.getTokenAtOffset(doc.offsetAt(range.start)) ?? return [];
		switch token.tok {
			case Const(CIdent("is")):
				return extractBinop(doc, tokens, uri, token, range);
			case Const(_), Kwd(KwdNew):
				final token = preDotToken(token);
				final hasSelection = !range.isEmpty();
				if (!hasSelection && TokenTreeUtils.isInFunctionScope(token))
					return [];
				if (isTypePosition(token))
					return [];
				// disallow full obj extraction when cursor is in `{nam|e: value}`
				if (TokenTreeUtils.isAnonStructureField(token))
					return [];
				if (isFieldAssign(token))
					return [];
				final action:Null<CodeAction> = makeExtractVarAction(doc, tokens, uri, token, range);
				return action == null ? [] : [action];
			case BrOpen, BrClose if (TokenTreeUtils.isAnonStructure(token)):
				final action:Null<CodeAction> = makeExtractVarAction(doc, tokens, uri, token, range);
				return action == null ? [] : [action];
			case BrOpen, BrClose:
				// `{` or `}` of an anon function body — extract the whole arrow/function
				final fn = TokenTreeUtils.getAnonFunctionFromBlock(token);
				if (fn != null)
					return extractAnonFunction(doc, tokens, uri, fn, range);
				return [];
			case Arrow:
				// cursor on `->` — extract the whole `args -> body`
				return extractAnonFunction(doc, tokens, uri, token, range);
			case Kwd(KwdFunction) if (TokenTreeUtils.isAnonFunction(token)):
				// cursor on `function` keyword of anon `function() { ... }`
				return extractAnonFunction(doc, tokens, uri, token, range);
			case POpen:
				// `(` of arrow/anon-function args
				final fn = TokenTreeUtils.getAnonFunctionFromPOpen(token);
				if (fn != null)
					return extractAnonFunction(doc, tokens, uri, fn, range);
				final token = token.getFirstChild();
				if (token != null && token.tok != PClose) {
					final action:Null<CodeAction> = makeExtractVarAction(doc, tokens, uri, token, range);
					return action == null ? [] : [action];
				}
				return [];
			case Binop(OpAssign), Binop(OpAssignOp(_)):
				return [];
			case Binop(_):
				// cursor on a binary operator (`||`, `&&`, `+`, etc)
				// extract the whole binop expression
				return extractBinop(doc, tokens, uri, token, range);
			case BkOpen, BkClose:
				final action:Null<CodeAction> = makeExtractVarAction(doc, tokens, uri, token, range);
				return action == null ? [] : [action];
			default:
				return [];
		}
	}

	function extractBinop(doc:HaxeDocument, tokens:TokenTreeManager, uri:DocumentUri, binop:TokenTree, range:Range):Array<CodeAction> {
		final left = binop.parent ?? return [];
		final left = preDotToken(left);
		final right = binop.getFirstChild() ?? return [];
		final lastRight = TokenTreeCheckUtils.getLastToken(right) ?? right;
		final start = tokens.getPos(left).min;
		final end = tokens.getPos(lastRight).max;
		final binopRange = doc.rangeAt(start, end);
		final action:Null<CodeAction> = makeExtractVarAction(doc, tokens, uri, left, binopRange);
		return action == null ? [] : [action];
	}

	function extractAnonFunction(doc:HaxeDocument, tokens:TokenTreeManager, uri:DocumentUri, fnRoot:TokenTree, range:Range):Array<CodeAction> {
		// for arrow: range covers `args -> body` (args = Arrow.parent: POpen or single arg ident).
		// for `function`: range covers `function (...) { ... }` (the whole KwdFunction subtree).
		final startToken = if (fnRoot.tok == Arrow) fnRoot.parent ?? return [] else fnRoot;
		final lastToken = getLastNonCommaToken(fnRoot) ?? fnRoot;
		final start = tokens.getPos(startToken).min;
		final end = tokens.getPos(lastToken).max;
		final fnRange = doc.rangeAt(start, end);
		final action:Null<CodeAction> = makeExtractVarAction(doc, tokens, uri, fnRoot, fnRange);
		return action == null ? [] : [action];
	}

	function isFieldAssign(token:TokenTree):Bool {
		switch token.tok {
			case Binop(OpAssign), Binop(OpAssignOp(_)):
				return true;
			case _:
				final first = token.getFirstChild() ?? return false;
				return isFieldAssign(first);
		}
	}

	function isTypePosition(token:TokenTree):Bool {
		var parent:Null<TokenTree> = token.parent;
		while (parent != null) {
			switch parent.tok {
				case DblDot:
					return switch TokenTreeCheckUtils.getColonType(parent) {
						case TypeHint, TypeCheck: true;
						case _: false;
					}
				case Const(CIdent("is")):
					return true;
				default:
			}
			token = parent;
			parent = parent.parent;
		}
		return false;
	}

	function lastDotName(token:Null<TokenTree>):String {
		// last ident of a dot-chain (`obj.foo.bar` -> `bar`, `new pkg.Foo()` -> `Foo`)
		var tok = token;
		while (tok != null) {
			final child = tok.getFirstChild();
			if (child != null && (child.tok == Dot || child.tok == QuestionDot))
				tok = child.getFirstChild();
			else
				break;
		}
		if (tok == null)
			return "value";
		return TokenTreeCheckUtils.getName(tok) ?? "value";
	}

	function makeExtractVarAction(doc:HaxeDocument, tokens:TokenTreeManager, uri:DocumentUri, token:TokenTree, range:Range):Null<CodeAction> {
		// use token at the selection end for `foo = Type.foo` names
		final endToken:Null<TokenTree> = tokens.getTokenAtOffset(doc.offsetAt(range.end)) ?? token;
		var text = switch token.tok {
			case Arrow, Kwd(KwdFunction): "callback";
			case Kwd(KwdNew): lastDotName(token.getFirstChild());
			case Const(CIdent(_)) if (range.isEmpty()): lastDotName(token);
			case _: switch endToken.tok {
					case Const(CString(s)): s;
					case Const(CInt(v, s)): s ?? "value";
					case Const(CFloat(f, s)): s ?? "value";
					case BrOpen, BrClose: "obj";
					case BkOpen, BkClose: "arr";
					case Const(CIdent(s)): s ?? "value";
					case _: "value";
				}
		}
		// generate a var name
		var name:String = ~/[^A-Za-z0-9]/g.replace(text, "_");
		name = ~/_+/g.replace(name, "_");
		name = ~/(^_|_$)/g.replace(name, "");
		if (~/^[0-9]/.match(name))
			name = "_" + name;
		if (name.length > 50)
			name = name.substr(0, 50);
		// detect PascalCase and convert to camelCase
		if (name.length > 1 && name.charAt(1).toLowerCase() == name.charAt(1)) {
			name = name.charAt(0).toLowerCase() + name.substr(1);
		} else {
			name = name.toLowerCase();
		}
		if (name.length <= 0)
			return null;

		final parent:Null<TokenTree> = findParentInLocalScope(token);
		if (parent == null)
			return null;
		final extractionRange = range.isEmpty() ? getExtractionRange(doc, token) : trimSelectionRange(doc, tokens, range);
		if (extractionRange == null)
			return null;
		final fullText = doc.getText(extractionRange);
		// insert var before parent
		final varInsertPos:Position = doc.positionAt(tokens.getTreePos(parent).min);

		final isSnippet = context.hasClientCommandSupport("haxe.codeAction.insertSnippet");
		if (isSnippet)
			name = '$${1:$name}';
		// indentation before var pos
		final prefix:String = doc.getText({start: {line: varInsertPos.line, character: 0}, end: varInsertPos});
		var exprText = FormatterHelper.formatText(doc, context, '$fullText;', ExpressionLevel);
		exprText = exprText.split("\n").mapi((i, s) -> i == 0 ? s : '$prefix$s').join("\n");
		final newConstText:String = 'final $name = $exprText';

		var fullText = newConstText;
		fullText += doc.getText({
			start: doc.positionAt(doc.offsetAt(varInsertPos)),
			end: doc.positionAt(doc.offsetAt(extractionRange.start))
		});
		fullText += name;
		if (isSnippet)
			fullText += "$0";

		final editRange = varInsertPos.toRange().union(extractionRange);
		final action:CodeAction = {
			title: "Extract to var in enclosing scope",
			kind: RefactorExtract,
		}
		if (isSnippet) {
			action.command = {
				title: "Insert Snippet",
				command: "haxe.codeAction.insertSnippet",
				arguments: [uri.toString(), editRange, fullText]
			}
		} else {
			final edit = WorkspaceEditHelper.replaceText(editRange, fullText);
			action.edit = WorkspaceEditHelper.create(doc, [edit]);
		}
		return action;
	}

	function findParentInLocalScope(token:TokenTree):Null<TokenTree> {
		var parent:Null<TokenTree> = token.parent;
		while (parent != null) {
			switch parent.tok {
				// inside case "block"
				case DblDot if (TokenTreeCheckUtils.getColonType(parent) == SwitchCase):
					return token;
				// case if-guards
				case Kwd(KwdCase):
					final parent = parent.access().findParent(helper -> helper?.token.tok.match(Kwd(KwdSwitch)));
					return parent?.token;
				case Kwd(KwdFunction | KwdFor):
					return null;
				case BrOpen:
					if (!TokenTreeUtils.isAnonStructure(parent))
						return token;
				default:
			}
			token = parent;
			parent = parent.parent;
		}
		return null;
	}

	function trimSelectionRange(doc:HaxeDocument, tokens:TokenTreeManager, range:Range):Range {
		// drop `;` from the end
		final endOffset = doc.offsetAt(range.end);
		final endToken = tokens.getTokenAtOffset(endOffset);
		if (endToken != null && endToken.tok == Semicolon && tokens.getPos(endToken).max == endOffset) {
			return {start: range.start, end: doc.positionAt(tokens.getPos(endToken).min)};
		}
		return range;
	}

	function getExtractionRange(doc:HaxeDocument, token:TokenTree):Null<Range> {
		final tokens = findExtractionRangeTokens(token);
		// trace("getExtractionRange:", tokens);
		var fullRange:Null<Range> = null;
		for (token in tokens) {
			if (token == null)
				continue;
			final range = doc.rangeAt(token.pos.min, token.pos.max, Utf8);
			if (fullRange == null) {
				fullRange = range;
				continue;
			}
			fullRange = fullRange.union(range);
		}
		return fullRange;
	}

	function preDotToken(token:TokenTree):TokenTree {
		final parent = token.parent ?? return token;
		switch parent.tok {
			case Kwd(KwdNew):
				return parent;
			case Dot, QuestionDot:
				final prevToken = parent.parent ?? return token;
				if (!token.isCIdent())
					return token;
				return preDotToken(prevToken);
			case _:
		}
		return token;
	}

	function findExtractionRangeTokens(token:TokenTree):Array<Null<TokenTree>> {
		if (token.tok == BrClose || token.tok == BkClose) {
			token = token.parent ?? return [];
		}
		// extract full object/array
		switch token.tok {
			case BrOpen:
				return [token, getLastNonCommaToken(token)];
			case BkOpen:
				final parent = token.parent ?? return [];
				final isArrAccess = parent.isCIdent() || parent.matches(BkOpen);
				if (!isArrAccess) {
					return [token, getLastNonCommaToken(token)];
				} else {
					token = parent;
				}
			case _:
		}

		var parent:Null<TokenTree> = token.parent;
		while (parent != null) {
			switch parent.tok {
				case Dot, QuestionDot:
					// skip to start of foo.bar.baz
					if (parent.parent?.isCIdent() == true) {
						parent = parent.parent ?? return [];
					}
				case BrOpen:
					final first = token.getFirstChild();
					final hasDot = first?.tok == Dot || first?.tok == QuestionDot;
					final last = hasDot ? first : token;
					return [token, getLastNonCommaToken(last)];
				case DblDot, Binop(_), Kwd(_):
					switch parent.tok {
						case Kwd(KwdNew | KwdVar | KwdFinal):
							return [];
						case _:
							return [token, getValueEndToken(token)];
					}
				case POpen, BkOpen:
					final endBracket:tokentree.TokenTreeDef = switch parent.tok {
						case POpen: PClose;
						case BkOpen: BkClose;
						case _: return [];
					}
					final tokens:Array<Null<TokenTree>> = [token];
					final firstChild = token.getFirstChild();
					// don't extract arrow function args
					if (firstChild?.tok == Arrow || parent.access().firstOf(Arrow) != null)
						return [];
					if (firstChild == null)
						return tokens;
					final last = getValueEndToken(token) ?? return tokens;
					tokens.push(last);
					return tokens;
				case Question:
					// ternary branch `cond ? a : b` — extract just this branch's value
					return [token, getValueEndToken(token)];
				case Unop(OpNot):
					return [token, getValueEndToken(token)];
				default:
			}
			token = parent;
			parent = parent.parent;
		}
		return [];
	}

	function getLastToken(token:Null<TokenTree>):Null<TokenTree> {
		if (token == null)
			return null;
		return TokenTreeCheckUtils.getLastToken(token);
	}

	function getValueEndToken(token:TokenTree):Null<TokenTree> {
		final children = token.children;
		if (children == null || children.length <= 0)
			return token;
		final lastChild = children[children.length - 1];
		final trailingOp = switch lastChild.tok {
			case Binop(_), Question, Const(CIdent("is")), Comma, Semicolon: true;
			case DblDot: TokenTreeCheckUtils.getColonType(lastChild) == TypeCheck;
			case _: false;
		}
		if (trailingOp) {
			// value is just the head token (e.g. `a` in `a ?? b`)
			if (children.length == 1)
				return token;
			return getValueEndToken(children[children.length - 2]);
		}
		return getValueEndToken(lastChild);
	}

	function getLastNonCommaToken(token:Null<TokenTree>):Null<TokenTree> {
		var last = getLastToken(token);
		if (last == null)
			return last;
		if (last.tok == Comma || last.tok == Semicolon) {
			last = last.previousSibling ?? return last.parent;
			// [Dot(...), Semicolon] case
			return getLastNonCommaToken(last);
		}
		return last;
	}
}

package haxeLanguageServer.features.haxe.codeAction;

import haxeLanguageServer.features.haxe.codeAction.CodeActionFeature.CodeActionContributor;
import haxeLanguageServer.helper.FormatterHelper;
import haxeLanguageServer.helper.WorkspaceEditHelper;
import haxeLanguageServer.tokentree.TokenTreeManager;
import languageServerProtocol.Types.CodeAction;
import languageServerProtocol.Types.TextDocumentEdit;
import tokentree.TokenTree;
import tokentree.utils.TokenTreeCheckUtils;

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
		return try {
			// only look at token at range start
			final token = tokens.getTokenAtOffset(doc.offsetAt(range.start)) ?? return [];
			switch token.tok {
				case Const(_):
					final token = preDotToken(token);
					if (isFunctionScope(token))
						return [];
					if (isTypeHint(token))
						return [];
					// disallow full obj extraction when cursor is in `{nam|e: value}`
					if (isAnonStructureField(token))
						return [];
					if (isFieldAssign(token))
						return [];
					final action:Null<CodeAction> = makeExtractVarAction(doc, tokens, uri, token, range);
					if (action == null) [] else [action];
				case BrOpen, BrClose if (isAnonStructure(token)):
					final action:Null<CodeAction> = makeExtractVarAction(doc, tokens, uri, token, range);
					if (action == null) [] else [action];
				case BkOpen, BkClose:
					final action:Null<CodeAction> = makeExtractVarAction(doc, tokens, uri, token, range);
					if (action == null) [] else [action];
				default: [];
			}
		} catch (e) {
			[];
		}
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

	function isTypeHint(token:TokenTree):Bool {
		var parent:Null<TokenTree> = token.parent;
		while (parent != null) {
			switch parent.tok {
				case DblDot: // not anon structure
					return parent.parent!.parent!.tok != BrOpen;
				default:
			}
			token = parent;
			parent = parent.parent;
		}
		return false;
	}

	function isFunctionScope(token:TokenTree):Bool {
		final brOpen = token.parent ?? return false;
		if (brOpen.tok != BrOpen)
			return false;
		final name = brOpen.parent ?? return false;
		if (name.tok.match(Kwd(_) | Arrow))
			return true;
		final fun = name.parent ?? return false;
		return fun.tok.match(Kwd(_));
	}

	function isAnonStructure(brToken:TokenTree):Bool {
		if (brToken.tok == BrClose)
			brToken = brToken.parent ?? return false;
		final first = brToken!.getFirstChild() ?? return false;
		final colon = first.getFirstChild() ?? return false;
		if (colon.tok.match(DblDot) && !colon.nextSibling!.tok.match(Semicolon)) {
			return true;
		}
		return false;
	}

	function isAnonStructureField(token:TokenTree):Bool {
		final parent = token.parent ?? return false;
		if (!isAnonStructure(parent))
			return false;
		final colon = token.getFirstChild() ?? return false;
		return colon.tok.match(DblDot);
	}

	function makeExtractVarAction(doc:HaxeDocument, tokens:TokenTreeManager, uri:DocumentUri, token:TokenTree, range:Range):Null<CodeAction> {
		// use token at the selection end for `foo = Type.foo` names
		final endToken:Null<TokenTree> = tokens.getTokenAtOffset(doc.offsetAt(range.end)) ?? token;
		var text = switch endToken.tok {
			case Const(CString(s)): s;
			case Const(CInt(v, s)): s ?? "value";
			case Const(CFloat(f, s)): s ?? "value";
			case BrOpen, BrClose: "obj";
			case BkOpen, BkClose: "arr";
			case Const(CIdent(s)): s ?? "value";
			case _: "value";
		}
		// generate a var name
		var name:String = ~/[^A-Za-z0-9]/g.replace(text, "_");
		name = ~/^[0-9]/g.replace(name, "_");
		name = ~/_+/g.replace(name, "_");
		name = ~/(^_|_$)/g.replace(name, "");
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
		// trace("parent: ", parent);
		final extractionRange = range.isEmpty() ? getExtractionRange(doc, token) : range;
		if (extractionRange == null)
			return null;
		final fullText = doc.getText(extractionRange);
		final varInsertPos:Position = doc.positionAt(tokens.getTreePos(parent).min);

		final edits:Array<TextEdit> = [];
		// insert var before parent
		final prefix:String = doc.getText({start: {line: varInsertPos.line, character: 0}, end: varInsertPos});
		final newConstText:String = FormatterHelper.formatText(doc, context, 'final $name = $fullText;', ExpressionLevel) + '$prefix';
		edits.push(WorkspaceEditHelper.insertText(varInsertPos, newConstText));

		edits.push(WorkspaceEditHelper.replaceText(extractionRange, name));

		final textEdit:TextDocumentEdit = WorkspaceEditHelper.textDocumentEdit(uri, edits);
		return {
			title: "Extract to var in enclosing scope",
			kind: RefactorExtract,
			edit: {
				documentChanges: [textEdit]
			}
		};
	}

	function findParentInLocalScope(token:TokenTree):Null<TokenTree> {
		var parent:Null<TokenTree> = token.parent;
		while (parent != null) {
			switch parent.tok {
				case Kwd(KwdFunction | KwdCase | KwdFor):
					return null;
				case BrOpen:
					if (!isAnonStructure(parent))
						return token;
				default:
			}
			token = parent;
			parent = parent.parent;
		}
		return null;
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
		switch token.tok {
			case BrOpen, BkOpen: // extract full object/array
				return [token, getLastNonCommaToken(token)];
			case _:
		}

		var parent:Null<TokenTree> = token.parent;
		while (parent != null) {
			switch parent.tok {
				case Dot, QuestionDot:
					// skip to start of foo.bar.baz
					if (parent.parent!.isCIdent() == true) {
						parent = parent.parent ?? return [];
					}
				case DblDot, Binop(_), Kwd(_):
					switch parent.tok {
						case Kwd(KwdNew | KwdVar | KwdFinal):
							return [];
						case _:
							// end of a.b expr is inside of Dot
							final first = token.getFirstChild();
							final hasDot = first!.tok == Dot || first!.tok == QuestionDot;
							final last = hasDot ? first : token;
							return [token, getLastNonCommaToken(last)];
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
					if (firstChild!.tok == Arrow || parent.access().firstOf(Arrow) != null)
						return [];
					if (firstChild == null)
						return tokens;
					final hasDot = firstChild.tok == Dot || firstChild.tok == QuestionDot;
					final isCall = firstChild.tok == POpen;
					final isNew = token.tok.match(Kwd(KwdNew));
					var lastParent = (hasDot || isCall || isNew) ? firstChild : token;
					var last = getLastToken(lastParent) ?? return tokens;
					if (last.tok.match(Comma | Binop(_))) {
						last = last.parent ?? return tokens;
					}
					tokens.push(last);
					return tokens;
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

	function getLastNonCommaToken(token:Null<TokenTree>):Null<TokenTree> {
		var last = getLastToken(token);
		if (last == null)
			return last;
		if (last.tok == Comma || last.tok == Semicolon)
			last = last.previousSibling ?? last.parent;
		return last;
	}
}

package haxeLanguageServer.features.codeAction;

import haxeLanguageServer.helper.FormatterHelper;
import haxeLanguageServer.helper.WorkspaceEditHelper;
import tokentree.TokenTree;

using tokentree.TokenTreeAccessHelper;

class ExtractConstantFeature {
	final context:Context;

	public function new(context:Context) {
		this.context = context;
		context.registerCodeActionContributor(extractConstant);
	}

	function extractConstant(params:CodeActionParams):Array<CodeAction> {
		var doc = context.documents.get(params.textDocument.uri);
		return internalExtractConstant(doc, params.textDocument.uri, params.range);
	}

	function internalExtractConstant(doc:TextDocument, uri:DocumentUri, range:Range):Array<CodeAction> {
		try {
			if ((doc.tokens == null) || (doc.tokens.tree == null))
				return [];

			// only look at token at range start
			var token:Null<TokenTree> = doc.tokens.getTokenAtOffset(doc.offsetAt(range.start));
			if (token == null)
				return [];

			// must be a Const(CString(_))
			switch (token.tok) {
				case Const(CString(s)):
					var action:Null<CodeAction> = makeExtractConstAction(doc, uri, token, s);
					if (action == null)
						return [];
					return [action];
				default:
					return [];
			}
		} catch (e:Any) {}
		return [];
	}

	function makeExtractConstAction(doc:TextDocument, uri:DocumentUri, token:TokenTree, text:String):Null<CodeAction> {
		if ((text == null) || (text == ""))
			return null;

		if (shouldSkipToken(token))
			return null;

		// skip string literals with interpolation
		var fullText:String = doc.getText(doc.rangeAt2(doc.tokens.getPos(token)));
		if ((fullText.startsWith("'")) && (~/[$]/g.match(text)))
			return null;

		// generate a const name
		var name:String = ~/[^A-Za-z0-9]/g.replace(text, "_");
		name = ~/^[0-9]/g.replace(name, "_");
		name = ~/_+/g.replace(name, "_");
		name = ~/(^_|_$)/g.replace(name, "");
		name = name.toUpperCase();
		if (name.length <= 0)
			return null;

		// find parent type and insert position for const
		var type:Null<TokenTree> = findParentType(token);
		if (type == null)
			return null;
		var firstToken:Null<TokenTree> = type.access().firstChild().isCIdent().firstOf(BrOpen).firstChild().token;
		if (firstToken == null)
			return null;
		var constInsertPos:Position = doc.positionAt(doc.tokens.getTreePos(firstToken).min);

		// find all occurrences of string constant
		var occurrences:Array<TokenTree> = type.filterCallback(function(token:TokenTree, index:Int):FilterResult {
			switch (token.tok) {
				case Const(CString(s)):
					if (s == text)
						return FOUND_SKIP_SUBTREE;
					return GO_DEEPER;
				default:
					return GO_DEEPER;
			}
		});

		var edits:Array<TextEdit> = [];

		// insert const into type body
		var prefix:String = doc.getText({start: {line: constInsertPos.line, character: 0}, end: constInsertPos});
		var newConstText:String = FormatterHelper.formatText(doc, context, 'static inline var $name = $fullText;', FIELD_LEVEL) + '\n$prefix';
		edits.push(WorkspaceEditHelper.insertText(constInsertPos, newConstText));

		// replace all occurrences with const name
		for (occurrence in occurrences) {
			edits.push(WorkspaceEditHelper.replaceText(doc.rangeAt2(doc.tokens.getPos(occurrence)), name));
		}

		var textEdit:TextDocumentEdit = WorkspaceEditHelper.textDocumentEdit(uri, edits);
		return {
			title: "Extract constant",
			kind: RefactorExtract,
			edit: {
				documentChanges: [textEdit]
			}
		};
	}

	function shouldSkipToken(token:TokenTree):Bool {
		var parent:Null<TokenTree> = token.parent;
		if (parent == null || parent.tok == null) {
			return true;
		}
		switch (parent.tok) {
			case BrOpen:
				return true;
			case POpen:
				// prevent const extraction inside metadata
				var atToken:Null<TokenTree> = parent.access().parent().isCIdent().parent().token;
				if (atToken == null) {
					return false;
				}
				switch (atToken.tok) {
					case At:
						return true;
					case DblDot:
						return atToken.access().parent().is(At).exists();
					default:
						return false;
				}
			case Binop(OpLt):
				return true;
			case Binop(OpAssign):
				// prevent const extraction from class fields
				var varToken:Null<TokenTree> = parent.access().parent().isCIdent().parent().token;
				if (varToken != null) {
					switch (varToken.tok) {
						case Kwd(KwdVar) | Kwd(KwdFinal):
							return varToken.access()
								.parent()
								.is(BrOpen)
								.parent()
								.isCIdent()
								.parent()
								.is(Kwd(KwdClass))
								.exists();
						default:
					}
				}
			default:
		}
		return false;
	}

	function findParentType(token:TokenTree):Null<TokenTree> {
		var parent:Null<TokenTree> = token.parent;
		while ((parent != null) && (parent.tok != null)) {
			switch (parent.tok) {
				case Kwd(KwdClass), Kwd(KwdAbstract):
					return parent;
				default:
			}
			parent = parent.parent;
		}
		return null;
	}
}

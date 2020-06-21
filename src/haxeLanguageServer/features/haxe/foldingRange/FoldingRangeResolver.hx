package haxeLanguageServer.features.haxe.foldingRange;

import tokentree.TokenTree;

using tokentree.TokenTreeAccessHelper;

class FoldingRangeResolver {
	static final regionStartPattern = ~/^\s*[#{]?\s*region\b/;
	static final regionEndPattern = ~/^\s*[#}]?\s*end ?region\b/;

	final document:HaxeDocument;
	final lineFoldingOnly:Bool;

	public function new(document:HaxeDocument, capabilities:Null<TextDocumentClientCapabilities>) {
		this.document = document;
		lineFoldingOnly = capabilities!.foldingRange!.lineFoldingOnly;
	}

	public function resolve():Array<FoldingRange> {
		final ranges:Array<FoldingRange> = [];
		function add(start:Position, end:Position, ?kind:FoldingRangeKind) {
			final range:FoldingRange = {
				startLine: start.line,
				endLine: end.line
			};
			if (!lineFoldingOnly) {
				range.startCharacter = start.character;
				range.endCharacter = end.character;
			}
			if (kind != null) {
				range.kind = kind;
			}
			ranges.push(range);
		}

		function addRange(range:haxe.macro.Expr.Position, ?kind:FoldingRangeKind) {
			final start = document.positionAt(range.min);
			final end = document.positionAt(range.max);
			add(start, end, kind);
		}

		var firstImport = null;
		var lastImport = null;
		final conditionalStack = [];
		final regionStack = [];
		final tokens = document.tokens;
		tokens.tree.filterCallback(function(token:TokenTree, _) {
			switch token.tok {
				case BrOpen, Const(CString(_)), BkOpen:
					final range = tokens.getTreePos(token);
					final start = document.positionAt(range.min);
					final end = getEndOfPreviousLine(range.max);
					if (end.line > start.line) {
						add(start, end);
					}

				case Kwd(KwdCase), Kwd(KwdDefault):
					addRange(tokens.getTreePos(token));

				case Comment(_):
					addRange(tokens.getTreePos(token), Comment);

				case CommentLine(s) if (regionStartPattern.match(s)):
					regionStack.push(tokens.getPos(token).max);

				case CommentLine(s) if (regionEndPattern.match(s)):
					final start = regionStack.pop();
					if (start != null) {
						final end = tokens.getPos(token);
						addRange({file: end.file, min: start, max: end.max}, Region);
					}

				case Kwd(KwdImport), Kwd(KwdUsing):
					if (firstImport == null) {
						firstImport = token;
					}
					lastImport = token;

				case Sharp(sharp):
					// everything except `#if` ends a range / adds a folding marker
					if (sharp == "else" || sharp == "elseif" || sharp == "end") {
						final start = conditionalStack.pop();
						final pos = tokens.getPos(token);
						final end = getEndOfPreviousLine(pos.max);
						if (start != null && end.line > start.line) {
							add(start, end);
						}
					}

					// everything except `#end` starts a range
					if (sharp == "if" || sharp == "else" || sharp == "elseif") {
						final pClose = token.access().firstChild().is(POpen).lastChild().is(PClose).token;
						final pos = if (pClose == null) tokens.getPos(token) else tokens.getPos(pClose);
						final start = document.positionAt(pos.max);
						start.character++;
						conditionalStack.push(start);
					}

				case _:
			}
			return GO_DEEPER;
		});

		if (lastImport != null && firstImport != lastImport) {
			final start = tokens.getPos(firstImport);
			final end = tokens.getTreePos(lastImport);
			addRange({file: start.file, min: start.min, max: end.max}, Imports);
		}

		return ranges;
	}

	function getEndOfPreviousLine(offset:Int):Position {
		final endLine = document.positionAt(offset).line - 1;
		final endCharacter = document.lineAt(endLine).length - 1;
		return {line: endLine, character: endCharacter};
	}
}

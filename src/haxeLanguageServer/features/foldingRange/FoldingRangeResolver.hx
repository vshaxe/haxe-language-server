package haxeLanguageServer.features.foldingRange;

import tokentree.TokenTree;
import languageServerProtocol.protocol.FoldingRange.FoldingRangeClientCapabilities;

using tokentree.TokenTreeAccessHelper;

class FoldingRangeResolver {
	static final regionStartPattern = ~/^\s*[#{]?\s*region\b/;
	static final regionEndPattern = ~/^\s*[#}]?\s*end ?region\b/;

	final document:TextDocument;
	final lineFoldingOnly:Bool;

	public function new(document:TextDocument, capabilities:FoldingRangeClientCapabilities) {
		this.document = document;
		if (capabilities != null && capabilities.foldingRange != null) {
			lineFoldingOnly = capabilities.foldingRange.lineFoldingOnly;
		}
	}

	public function resolve():Array<FoldingRange> {
		var ranges:Array<FoldingRange> = [];
		function add(start:Position, end:Position, ?kind:FoldingRangeKind) {
			var range:FoldingRange = {
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
			var start = document.positionAt(range.min);
			var end = document.positionAt(range.max);
			add(start, end, kind);
		}

		var firstImport = null;
		var lastImport = null;
		var conditionalStack = [];
		var regionStack = [];
		var tokens = document.tokens;
		tokens.tree.filterCallback(function(token:TokenTree, _) {
			switch token.tok {
				case BrOpen, Const(CString(_)), BkOpen:
					var range = tokens.getTreePos(token);
					var start = document.positionAt(range.min);
					var end = getEndOfPreviousLine(range.max);
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
					var start = regionStack.pop();
					if (start != null) {
						var end = tokens.getPos(token);
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
						var start = conditionalStack.pop();
						var pos = tokens.getPos(token);
						var end = getEndOfPreviousLine(pos.max);
						if (start != null && end.line > start.line) {
							add(start, end);
						}
					}

					// everything except `#end` starts a range
					if (sharp == "if" || sharp == "else" || sharp == "elseif") {
						var pClose = token.access().firstChild().is(POpen).lastChild().is(PClose).token;
						var pos = if (pClose == null) tokens.getPos(token) else tokens.getPos(pClose);
						var start = document.positionAt(pos.max);
						start.character++;
						conditionalStack.push(start);
					}

				case _:
			}
			return GO_DEEPER;
		});

		if (lastImport != null && firstImport != lastImport) {
			var start = tokens.getPos(firstImport);
			var end = tokens.getTreePos(lastImport);
			addRange({file: start.file, min: start.min, max: end.max}, Imports);
		}

		return ranges;
	}

	function getEndOfPreviousLine(offset:Int):Position {
		var endLine = document.positionAt(offset).line - 1;
		var endCharacter = document.lineAt(endLine).length - 1;
		return {line: endLine, character: endCharacter};
	}
}

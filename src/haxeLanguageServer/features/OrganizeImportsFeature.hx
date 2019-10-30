package haxeLanguageServer.features;

import haxe.ds.ArraySort;
import haxeLanguageServer.helper.FormatterHelper;
import haxeLanguageServer.helper.WorkspaceEditHelper;
import tokentree.TokenTree;
import tokentree.TokenTreeBuilder;

class OrganizeImportsFeature {
	public static function organizeImports(doc:TextDocument, context:Context, unusedRanges:Array<Range>):Array<TextEdit> {
		if ((doc.tokens == null) || (doc.tokens.tree == null))
			return [];
		try {
			var imports:Array<TokenTree> = doc.tokens.tree.filterCallback(function(token:TokenTree, index:Int):FilterResult {
				switch (token.tok) {
					case Kwd(KwdImport), Kwd(KwdUsing):
						return FOUND_SKIP_SUBTREE;
					default:
				}
				return GO_DEEPER;
			});

			var importGroups:Map<Int, ImportGroup> = new Map<Int, ImportGroup>();
			for (i in imports) {
				var id:Int = -1;
				if (i.parent != null)
					id = i.parent.index;

				var group:Null<ImportGroup> = importGroups.get(id);
				if (group == null) {
					group = {
						id: id,
						startOffset: determineStartPos(i),
						imports: [],
						usings: []
					}
					importGroups.set(id, group);
				}
				var range:Range = doc.rangeAt2(i.getPos());
				var isUnused:Bool = false;
				for (r in unusedRanges) {
					if (r.contains(range)) {
						isUnused = true;
						break;
					}
				}
				if (isUnused)
					continue;

				switch (i.tok) {
					case Kwd(KwdImport):
						group.imports.push({
							token: i,
							text: doc.getText(range)
						});
					case Kwd(KwdUsing):
						group.usings.push({
							token: i,
							text: doc.getText(range)
						});
					default:
				}
			}
			return organizeImportGroups(doc, context, importGroups);
		} catch (e:Any) {}
		return [];
	}

	static function organizeImportGroups(doc:TextDocument, context:Context, importGroups:Map<Int, ImportGroup>):Array<TextEdit> {
		var edits:Array<TextEdit> = [];

		for (group in importGroups)
			edits = edits.concat(organizeImportGroup(doc, context, group));

		return edits;
	}

	static function organizeImportGroup(doc:TextDocument, context:Context, importGroup:ImportGroup):Array<TextEdit> {
		ArraySort.sort(importGroup.imports, sortImports);
		var newImports:String = importGroup.imports.map(i -> i.text).join("\n");

		ArraySort.sort(importGroup.usings, sortImports);
		var newUsings:String = importGroup.usings.map(i -> i.text).join("\n");

		var newText:String = FormatterHelper.formatText(doc, context, newImports + "\n" + newUsings, TokenTreeEntryPoint.TYPE_LEVEL);

		var edits:Array<TextEdit> = [];

		// remove all existing imports/usings from group
		for (i in importGroup.imports)
			edits.push(makeImportEdit(doc, i.token));

		for (i in importGroup.usings)
			edits.push(makeImportEdit(doc, i.token));

		// insert sorted imports/usings at startOffset
		var importInsertPos:Position = doc.positionAt(importGroup.startOffset);
		edits.push(WorkspaceEditHelper.insertText(importInsertPos, newText + "\n"));

		return edits;
	}

	static function makeImportEdit(doc:TextDocument, token:TokenTree):TextEdit {
		var range:Range = doc.rangeAt2(token.getPos());
		// TODO move marker to beginning of next line assumes imports are one line each
		// maybe look at document whitespace and remove all trailing?
		range.end.line++;
		range.end.character = 0;
		return WorkspaceEditHelper.removeText(range);
	}

	static function sortImports(a:ImportInfo, b:ImportInfo):Int {
		if (a.text < b.text)
			return -1;
		if (a.text > b.text)
			return 1;
		return 0;
	}

	static function determineStartPos(token:TokenTree):Int {
		return token.pos.min;
	}
}

typedef ImportGroup = {
	var id:Int;
	var startOffset:Int;
	var imports:Array<ImportInfo>;
	var usings:Array<ImportInfo>;
}

typedef ImportInfo = {
	var token:TokenTree;
	var text:String;
}

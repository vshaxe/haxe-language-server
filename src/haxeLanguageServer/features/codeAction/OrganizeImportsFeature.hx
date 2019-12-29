package haxeLanguageServer.features.codeAction;

import haxe.ds.ArraySort;
import haxeLanguageServer.helper.FormatterHelper;
import haxeLanguageServer.helper.WorkspaceEditHelper;
import tokentree.TokenTree;
import tokentree.TokenTreeBuilder;

class OrganizeImportsFeature {
	static final stdLibPackages:Array<String> = [
		"cpp", "cs", "eval", "flash", "haxe", "hl", "java", "js", "lua", "neko", "php", "python", "sys", "Any", "Array", "ArrayAccess", "Bool", "Class",
		"Date", "DateTools", "Dynamic", "EReg", "Enum", "EnumValue", "Float", "Int", "IntIterator", "Iterable", "Iterator", "KeyValueIterable",
		"KeyValueIterator", "Lambda", "List", "Map", "Math", "Null", "Reflect", "Single", "Std", "String", "StringBuf", "StringTools", "Sys", "SysError",
		"Type", "UInt", "UnicodeString", "ValueType", "Void", "Xml", "XmlType"
	];

	public static function organizeImports(doc:TextDocument, context:Context, unusedRanges:Array<Range>):Array<TextEdit> {
		if ((doc.tokens == null) || (doc.tokens.tree == null)) {
			return [];
		}
		try {
			var packageName:Null<String> = null;
			var imports:Array<TokenTree> = doc.tokens.tree.filterCallback(function(token:TokenTree, index:Int):FilterResult {
				switch (token.tok) {
					case Kwd(KwdImport) | Kwd(KwdUsing):
						return FOUND_SKIP_SUBTREE;
					case Kwd(KwdPackage):
						var child = token.getFirstChild();
						if (child == null) {
							return SKIP_SUBTREE;
						}
						switch (child.tok) {
							case Kwd(_):
								packageName = '$child';
							case Const(CIdent(s)):
								packageName = s;
							default:
						}
						return SKIP_SUBTREE;
					case Sharp(_):
						return GO_DEEPER;
					default:
						return SKIP_SUBTREE;
				}
			});

			var importGroups:Map<Int, ImportGroup> = new Map<Int, ImportGroup>();
			var groupCount:Int = 0;
			for (i in imports) {
				var id:Int = -1;
				if (i.parent != null) {
					id = i.parent.index;
				}

				var group:Null<ImportGroup> = importGroups.get(id);
				if (group == null) {
					group = {
						id: id,
						startOffset: determineStartPos(doc, i),
						imports: [],
						usings: [],
						lastIndex: i.index
					}
					importGroups.set(id, group);
					groupCount++;
				}

				var range:Range = doc.rangeAt2(doc.tokens.getTreePos(i));
				var isUnused:Bool = false;
				for (r in unusedRanges) {
					if (r.contains(range)) {
						isUnused = true;
						break;
					}
				}
				if (isUnused) {
					continue;
				}

				var type:ImportType = determineImportType(i, packageName);
				switch (i.tok) {
					case Kwd(KwdImport):
						group.imports.push({
							token: i,
							text: doc.getText(range),
							type: type,
							range: range
						});
						group.lastIndex = i.index;
					case Kwd(KwdUsing):
						group.usings.push({
							token: i,
							text: doc.getText(range),
							type: type,
							range: range
						});
						group.lastIndex = i.index;
					default:
				}
			}
			return organizeImportGroups(doc, context, importGroups);
		} catch (e:Any) {}
		return [];
	}

	static function determineImportType(token:TokenTree, packageName:Null<String>):ImportType {
		var child:Null<TokenTree> = token.getFirstChild();
		if (child == null) {
			return Project;
		}
		var topLevelPack:String;
		switch (child.tok) {
			case Kwd(_):
				topLevelPack = '$child';
			case Const(CIdent(s)):
				topLevelPack = s;
			default:
				return Project;
		}
		if (stdLibPackages.contains(topLevelPack)) {
			return StdLib;
		}
		if (packageName == null) {
			return Project;
		}
		if (topLevelPack == packageName) {
			return Project;
		}
		return Library;
	}

	static function organizeImportGroups(doc:TextDocument, context:Context, importGroups:Map<Int, ImportGroup>):Array<TextEdit> {
		var edits:Array<TextEdit> = [];
		for (group in importGroups) {
			edits = edits.concat(organizeImportGroup(doc, context, group));
		}
		return edits;
	}

	static function organizeImportGroup(doc:TextDocument, context:Context, importGroup:ImportGroup):Array<TextEdit> {
		var sortFunc:Null<ImportSortFunction> = determineSortFunction(context);
		if (sortFunc == null) {
			return [];
		}

		ArraySort.sort(importGroup.imports, sortFunc);
		var newImports:String = importGroup.imports.map(i -> i.text).join("\n");

		ArraySort.sort(importGroup.usings, sortFunc);
		var newUsings:String = importGroup.usings.map(i -> i.text).join("\n");
		var delim:String = (importGroup.imports.length > 0 && importGroup.usings.length > 0) ? "\n" : "";

		var newText:String = FormatterHelper.formatText(doc, context, newImports + delim + newUsings, TokenTreeEntryPoint.TYPE_LEVEL);
		var edits:Array<TextEdit> = [];

		// remove all existing imports/usings from group
		for (i in importGroup.imports) {
			edits.push(makeImportEdit(doc, i.range, i.token.index == importGroup.lastIndex));
		}
		for (i in importGroup.usings) {
			edits.push(makeImportEdit(doc, i.range, i.token.index == importGroup.lastIndex));
		}

		// insert sorted imports/usings at startOffset
		var importInsertPos:Position = doc.positionAt(importGroup.startOffset);
		edits.push(WorkspaceEditHelper.insertText(importInsertPos, newText));

		return edits;
	}

	static function determineSortFunction(context:Context):ImportSortFunction {
		return switch (context.config.user.importsSortOrder) {
			case AllAlphabetical:
				sortImportsAllAlpha;
			case StdlibThenLibsThenProject:
				sortImportsStdlibThenLibsThenProject;
			case NonProjectThenProject:
				sortImportsNonProjectThenProject;
		}
	}

	static function makeImportEdit(doc:TextDocument, range:Range, isLast:Bool):TextEdit {
		// TODO move marker to beginning of next line assumes imports are one line each
		// maybe look at document whitespace and remove all trailing?
		range.end.line++;
		range.end.character = 0;

		var nextLineRange:Range = {
			start: range.end,
			end: {
				line: range.end.line + 1,
				character: 0
			}
		};
		var lineAfter:String = doc.getText(nextLineRange).trim();
		if (lineAfter.length <= 0 && !isLast) {
			range.end.line++;
		}
		return WorkspaceEditHelper.removeText(range);
	}

	static function sortImportsAllAlpha(a:ImportInfo, b:ImportInfo):Int {
		if (a.text < b.text) {
			return -1;
		}
		if (a.text > b.text) {
			return 1;
		}
		return 0;
	}

	static function sortImportsStdlibThenLibsThenProject(a:ImportInfo, b:ImportInfo):Int {
		if (a.type < b.type) {
			return -1;
		}
		if (a.type > b.type) {
			return 1;
		}
		if (a.text < b.text) {
			return -1;
		}
		if (a.text > b.text) {
			return 1;
		}
		return 0;
	}

	static function sortImportsNonProjectThenProject(a:ImportInfo, b:ImportInfo):Int {
		if (a.type == StdLib) {
			a.type = Library;
		}
		if (b.type == StdLib) {
			b.type = Library;
		}
		return sortImportsStdlibThenLibsThenProject(a, b);
	}

	static function determineStartPos(doc:TextDocument, token:TokenTree):Int {
		return doc.tokens.getPos(token).min;
	}
}

private typedef ImportGroup = {
	var id:Int;
	var startOffset:Int;
	var imports:Array<ImportInfo>;
	var usings:Array<ImportInfo>;
	var lastIndex:Int;
}

private typedef ImportInfo = {
	var token:TokenTree;
	var text:String;
	var type:ImportType;
	var range:Range;
}

private enum abstract ImportType(Int) {
	var StdLib;
	var Library;
	var Project;

	@:op(a < b)
	public function opLt(val:ImportType):Bool;

	@:op(a > b)
	public function opLt(val:ImportType):Bool;
}

private typedef ImportSortFunction = (a:ImportInfo, b:ImportInfo) -> Int;

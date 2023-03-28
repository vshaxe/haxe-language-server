package haxeLanguageServer.features.haxe.codeAction;

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

	public static function organizeImports(doc:HaxeDocument, context:Context, unusedRanges:Array<Range>):Array<TextEdit> {
		final tokens = doc.tokens;
		if (tokens == null) {
			return [];
		}
		return try {
			var packageName:Null<String> = null;
			final imports:Array<TokenTree> = tokens.tree.filterCallback(function(token:TokenTree, index:Int):FilterResult {
				switch token.tok {
					case Kwd(KwdImport) | Kwd(KwdUsing):
						return FoundSkipSubtree;
					case CommentLine(s):
						s = s.ltrim();
						if (s.startsWith("import ") || s.startsWith("using ")) {
							return FoundSkipSubtree;
						}
						return SkipSubtree;
					case Kwd(KwdPackage):
						final child = token.getFirstChild();
						if (child == null) {
							return SkipSubtree;
						}
						switch child.tok {
							case Kwd(_):
								packageName = '$child';
							case Const(CIdent(s)):
								packageName = s;
							default:
						}
						return SkipSubtree;
					case Sharp(_):
						return GoDeeper;
					default:
						return SkipSubtree;
				}
			});

			final importGroups = new Map<Int, ImportGroup>();
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
						startOffset: tokens.getPos(i).min,
						imports: [],
						usings: [],
						lastIndex: i.index
					}
					importGroups.set(id, group);
					groupCount++;
				}

				// get full line, including trailing comments
				final range:Range = doc.lineRangeAt(tokens.getTreePos(i).min);
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

				final type:ImportType = determineImportType(i, packageName);
				var text:String = doc.getText(range);
				switch i.tok {
					case Kwd(KwdImport):
						group.imports.push({
							token: i,
							text: text,
							sortText: text,
							type: type,
							range: range
						});
						group.lastIndex = i.index;
					case Kwd(KwdUsing):
						group.usings.push({
							token: i,
							text: text,
							sortText: text,
							type: type,
							range: range
						});
						group.lastIndex = i.index;
					case CommentLine(s):
						s = s.ltrim();
						if (s.startsWith("import ")) {
							group.imports.push({
								token: i,
								text: text,
								sortText: s,
								type: type,
								range: range
							});
							group.lastIndex = i.index;
						}
						if (s.startsWith("using ")) {
							group.usings.push({
								token: i,
								text: text,
								sortText: s,
								type: type,
								range: range
							});
							group.lastIndex = i.index;
						}
					default:
				}
			}
			organizeImportGroups(doc, context, importGroups);
		} catch (e) {
			[];
		}
	}

	static function determineImportType(token:TokenTree, packageName:Null<String>):ImportType {
		var topLevelPack:String;
		switch (token.tok) {
			case CommentLine(s):
				s = s.ltrim();
				if (s.startsWith("import ")) {
					s = s.substr(7);
				}
				if (s.startsWith("using ")) {
					s = s.substr(6);
				}
				var index = s.indexOf(".");
				if (index < 0) {
					index = s.indexOf(";");
					topLevelPack = s;
					if (index > 0) {
						topLevelPack = s.substring(0, index);
					}
				} else {
					topLevelPack = s.substring(0, index);
				}
			default:
				final child:Null<TokenTree> = token.getFirstChild();
				if (child == null) {
					return Project;
				}
				switch child.tok {
					case Kwd(_):
						topLevelPack = '$child';
					case Const(CIdent(s)):
						topLevelPack = s;
					default:
						return Project;
				}
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

	static function organizeImportGroups(doc:HxTextDocument, context:Context, importGroups:Map<Int, ImportGroup>):Array<TextEdit> {
		var edits:Array<TextEdit> = [];
		for (group in importGroups) {
			edits = edits.concat(organizeImportGroup(doc, context, group));
		}
		return edits;
	}

	static function organizeImportGroup(doc:HxTextDocument, context:Context, importGroup:ImportGroup):Array<TextEdit> {
		final sortFunc:Null<ImportSortFunction> = determineSortFunction(context);
		if (sortFunc == null) {
			return [];
		}

		ArraySort.sort(importGroup.imports, sortFunc);
		final newImports:String = importGroup.imports.map(i -> i.text).join("\n");

		ArraySort.sort(importGroup.usings, sortFunc);
		final newUsings:String = importGroup.usings.map(i -> i.text).join("\n");
		final importDelim:String = (importGroup.imports.length > 0) ? "\n" : "";
		final usingDelim:String = (importGroup.usings.length > 0) ? "\n" : "";

		var newText:String = FormatterHelper.formatText(doc, context, newImports + importDelim + newUsings + usingDelim, TokenTreeEntryPoint.TypeLevel);

		// add final newline in case it was stripped by the formatter configuration
		if (newText.charCodeAt(newText.length - 1) != "\n".code) {
			newText += "\n";
		}

		final edits:Array<TextEdit> = [];

		// remove all existing imports/usings from group
		for (i in importGroup.imports) {
			edits.push(makeImportEdit(doc, i.range, i.token.index == importGroup.lastIndex));
		}
		for (i in importGroup.usings) {
			edits.push(makeImportEdit(doc, i.range, i.token.index == importGroup.lastIndex));
		}

		// insert sorted imports/usings at startOffset
		final importInsertPos:Position = doc.positionAt(importGroup.startOffset);
		edits.push(WorkspaceEditHelper.insertText(importInsertPos, newText));

		return edits;
	}

	static function determineSortFunction(context:Context):ImportSortFunction {
		return switch context.config.user.importsSortOrder {
			case AllAlphabetical: sortImportsAllAlpha;
			case StdlibThenLibsThenProject: sortImportsStdlibThenLibsThenProject;
			case NonProjectThenProject: sortImportsNonProjectThenProject;
		}
	}

	static function makeImportEdit(doc:HxTextDocument, range:Range, isLast:Bool):TextEdit {
		// TODO move marker to beginning of next line assumes imports are one line each
		// maybe look at document whitespace and remove all trailing?
		range.end.line++;
		range.end.character = 0;

		final nextLineRange:Range = {
			start: range.end,
			end: {
				line: range.end.line + 1,
				character: 0
			}
		};
		final lineAfter:String = doc.getText(nextLineRange).trim();
		if (lineAfter.length <= 0 && !isLast) {
			range.end.line++;
		}
		return WorkspaceEditHelper.removeText(range);
	}

	static function sortImportsAllAlpha(a:ImportInfo, b:ImportInfo):Int {
		if (a.sortText < b.sortText) {
			return -1;
		}
		if (a.sortText > b.sortText) {
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
		if (a.sortText < b.sortText) {
			return -1;
		}
		if (a.sortText > b.sortText) {
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
}

private typedef ImportGroup = {
	final id:Int;
	final startOffset:Int;
	final imports:Array<ImportInfo>;
	final usings:Array<ImportInfo>;
	var lastIndex:Int;
}

private typedef ImportInfo = {
	final token:TokenTree;
	final text:String;
	final sortText:String;
	var type:ImportType;
	final range:Range;
}

private enum abstract ImportType(Int) {
	final StdLib;
	final Library;
	final Project;

	@:op(a < b)
	public function opLt(val:ImportType):Bool;

	@:op(a > b)
	public function opLt(val:ImportType):Bool;
}

private typedef ImportSortFunction = (a:ImportInfo, b:ImportInfo) -> Int;

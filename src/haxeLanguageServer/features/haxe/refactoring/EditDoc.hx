package haxeLanguageServer.features.haxe.refactoring;

import haxe.extern.EitherType;
import haxeLanguageServer.helper.FormatterHelper;
import languageServerProtocol.Types.CreateFile;
import languageServerProtocol.Types.CreateFileKind;
import languageServerProtocol.Types.DeleteFile;
import languageServerProtocol.Types.DeleteFileKind;
import languageServerProtocol.Types.RenameFile;
import languageServerProtocol.Types.RenameFileKind;
import refactor.edits.IEditableDocument;
import sys.FileSystem;
import tokentree.TokenTreeBuilder;

using Lambda;
using haxeLanguageServer.helper.PathHelper;

class EditDoc implements IEditableDocument {
	var list:EditList;
	var filePath:FsPath;
	var edits:Array<TextEdit>;
	var creates:Array<CreateFile>;
	var renames:Array<RenameFile>;
	var deletes:Array<DeleteFile>;
	final context:Context;
	final converter:Haxe3DisplayOffsetConverter;

	public function new(filePath:FsPath, list:EditList, context:Context, converter:Haxe3DisplayOffsetConverter) {
		this.filePath = filePath;
		this.list = list;
		this.context = context;
		this.converter = converter;
		edits = [];
		creates = [];
		renames = [];
		deletes = [];
	}

	public function addChange(edit:refactor.edits.FileEdit) {
		switch (edit) {
			case CreateFile(newFilePath):
				creates.push({
					kind: CreateFileKind.Create,
					uri: new FsPath(newFilePath).toUri(),
					options: {
						overwrite: false,
						ignoreIfExists: false
					}
				});
			case Move(newFilePath):
				renames.push({
					kind: RenameFileKind.Kind,
					oldUri: filePath.toUri(),
					newUri: new FsPath(newFilePath).toUri(),
					options: {
						overwrite: false,
						ignoreIfExists: false
					}
				});
			case DeleteFile(oldFilePath):
				deletes.push({
					kind: DeleteFileKind.Delete,
					uri: new FsPath(oldFilePath).toUri(),
					options: {
						recursive: false,
						ignoreIfNotExists: false
					}
				});
			case ReplaceText(text, pos, f):
				final range = posToRange(pos);
				text = correctFirstLineIndent(f, text, range);
				edits.push({range: range, newText: text});
			case InsertText(text, pos, f):
				final range = posToRange(pos);
				text = correctFirstLineIndent(f, text, range);
				edits.push({range: posToRange(pos), newText: text});
			case RemoveText(pos):
				edits.push({range: posToRange(pos), newText: ""});
		}
	}

	function correctFirstLineIndent(f:refactor.edits.FormatType, text:String, range:Range):String {
		switch (f) {
			case NoFormat:
			case Format(indentOffset, trimRight):
				text = FormatterHelper.formatSnippet(filePath, text, TokenTreeEntryPoint.FieldLevel, indentOffset);
				if (trimRight) {
					text = text.rtrim();
				}
				if (range.start.character != 0) {
					var doc:Null<HaxeDocument> = context.documents.getHaxe(filePath.toUri());
					if (doc != null) {
						final beforeRange:Range = {
							start: {
								line: range.start.line,
								character: 0
							},
							end: {
								line: range.start.line,
								character: range.start.character
							}
						};
						var beforeText = doc.getText(beforeRange);
						if (beforeText.trim().length == 0) {
							range.start.character = 0;
						} else {
							text = text.ltrim();
						}
					}
				}
		}
		return text;
	}

	public function posToRange(pos:refactor.discover.IdentifierPos):Range {
		if (!FileSystem.exists(filePath.toString())) {
			var posNull:Position = {line: 0, character: 0};
			return {start: posNull, end: posNull};
		}
		var doc:Null<HaxeDocument> = context.documents.getHaxe(filePath.toUri());
		if (doc == null) {
			// document currently not loaded -> load and find line number and character pos to build edit Range
			var content:String = sys.io.File.getContent(filePath.toString());
			var lineSeparator:String = detectLineSeparator(content);
			var separatorLength:Int = lineSeparator.length;
			var lines:Array<String> = content.split(lineSeparator);
			var startPos:Null<Position> = null;
			var endPos:Null<Position> = null;
			var curLineStart:Int = 0;
			var curLine:Int = 0;

			var startOffset:Int = converter.byteOffsetToCharacterOffset(content, pos.start);
			var endOffset:Int = converter.byteOffsetToCharacterOffset(content, pos.end);

			for (line in lines) {
				var length:Int = line.length + separatorLength;
				if (startOffset > curLineStart + length) {
					curLineStart += length;
					curLine++;
					continue;
				}
				if (startOffset >= curLineStart && startOffset < curLineStart + length) {
					startPos = {line: curLine, character: startOffset - curLineStart};
				}
				if (endOffset >= curLineStart && endOffset < curLineStart + length) {
					endPos = {line: curLine, character: endOffset - curLineStart};
					break;
				}
				curLineStart += length;
				curLine++;
			}
			if ((startPos == null) || (endPos == null)) {
				throw '$filePath not found';
			}
			return {start: cast startPos, end: cast endPos};
		}
		return doc.rangeAt(converter.byteOffsetToCharacterOffset(doc.content, pos.start), converter.byteOffsetToCharacterOffset(doc.content, pos.end));
	}

	function detectLineSeparator(code:String):String {
		var lineSeparator:String;
		for (i in 0...code.length) {
			var char = code.charAt(i);
			if ((char == "\r") || (char == "\n")) {
				lineSeparator = char;
				if ((char == "\r") && (i + 1 < code.length)) {
					char = code.charAt(i + 1);
					if (char == "\n") {
						lineSeparator += char;
					}
				}
				return lineSeparator;
			}
		}
		return "\n";
	}

	public function endEdits() {
		for (create in creates) {
			list.addEdit(create);
		}
		list.addEdit({
			textDocument: {
				uri: filePath.toUri(),
				version: null
			},
			edits: edits
		});
		for (rename in renames) {
			list.addEdit(rename);
		}
		for (delete in deletes) {
			list.addEdit(delete);
		}
	}
}

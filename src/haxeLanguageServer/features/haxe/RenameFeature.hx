package haxeLanguageServer.features.haxe;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
#if debug
import haxe.extern.EitherType;
#else
import haxe.DynamicAccess;
import haxeLanguageServer.hxParser.RenameResolver;
#end

class RenameFeature {
	final context:Context;
	final converter:Haxe3DisplayOffsetConverter;

	public function new(context:Context) {
		this.context = context;

		converter = new Haxe3DisplayOffsetConverter();

		context.languageServerProtocol.onRequest(RenameRequest.type, onRename);
	}

	function onRename(params:RenameParams, token:CancellationToken, resolve:WorkspaceEdit->Void, reject:ResponseError<NoData>->Void) {
		final uri = params.textDocument.uri;
		final doc = context.documents.getHaxe(uri);

		#if debug
		var fileName:String = uri.toFsPath().toString();
		var workspacePath:String = context.workspacePath.toString();
		if (fileName.startsWith(workspacePath)) {
			fileName = fileName.substr(workspacePath.length + 1);
		}

		if (doc == null || !uri.isFile()) {
			return reject.noFittingDocument(uri);
		}
		var usageContext:refactor.discover.UsageContext = {
			fileName: "",
			file: null,
			usageCollector: new refactor.discover.UsageCollector(),
			nameMap: new refactor.discover.NameMap(),
			fileList: new refactor.discover.FileList(),
			typeList: new refactor.discover.TypeList(),
			type: null
		};

		// TODO abort if there are unsaved documents (rename operates on fs, so positions might be off)

		// TODO use workspace / compilation server source folders or maybe a user config
		var srcFolders:Array<String> = ["src", "test"];
		if (context.config.user.renameSourcFolders != null) {
			srcFolders = context.config.user.renameSourcFolders;
		}

		refactor.discover.TraverseSources.traverseSources(srcFolders, usageContext);
		usageContext.usageCollector.updateImportHx(usageContext);
		var editList:EditList = new EditList();

		var result:refactor.RefactorResult = refactor.Refactor.rename({
			nameMap: usageContext.nameMap,
			fileList: usageContext.fileList,
			typeList: usageContext.typeList,
			what: {
				fileName: fileName,
				toName: params.newName,
				pos: converter.characterOffsetToByteOffset(doc.content, doc.offsetAt(params.position))
			},
			forRealExecute: true,
			docFactory: function(fileName:String) {
				var fullFileName:String = haxe.io.Path.join([Sys.getCwd(), fileName]);
				return new EditDoc(fullFileName, editList, context, converter);
			},
			verboseLog: function(text:String) {
				trace('[rename] $text');
			}
		});
		switch (result) {
			case NoChange:
				trace("nothing to do");
				reject(ResponseError.internalError("no change"));
			case NotFound:
				trace("could not find identifier at " + params.position);
				reject(ResponseError.internalError("could not find identifier at " + params.position));
			case Unsupported:
				trace("refactoring not supported at " + params.position);
				reject(ResponseError.internalError("refactoring not supported at " + params.position));
			case DryRun:
				trace("dry run");
				reject(ResponseError.internalError("dry run"));
			case Done:
				trace("changes were made");
				resolve({documentChanges: editList.documentChanges});
		}
		#else
		if (!~/[_A-Za-z]\w*/.match(params.newName)) {
			return reject(ResponseError.internalError("'" + params.newName + "' is not a valid identifier name."));
		}

		function invalidRename() {
			reject(ResponseError.internalError("Only local variables and function parameters can be renamed."));
		}

		context.gotoDefinition.onGotoDefinition(params, token, function(locations) {
			function noDeclaration() {
				reject(ResponseError.internalError("No declaration found."));
			}
			if (locations == null) {
				return noDeclaration();
			}
			final declaration = locations[0];
			if (declaration == null) {
				return noDeclaration();
			}
			if (declaration.uri != uri) {
				return invalidRename();
			}
			final parseTree = @:nullSafety(Off) doc.parseTree;
			if (parseTree == null) {
				return reject.noTokens();
			}
			final resolver = new RenameResolver(declaration.range, params.newName);
			resolver.walkFile(parseTree, Root);
			if (resolver.edits.length == 0) {
				return invalidRename();
			}

			final changes = new haxe.DynamicAccess();
			changes[uri.toString()] = resolver.edits;
			resolve({changes: changes});
		}, _ -> invalidRename());
		#end
	}
}

#if debug
class EditList {
	public var documentChanges:Array<EitherType<TextDocumentEdit, EitherType<CreateFile, EitherType<RenameFile, DeleteFile>>>>;

	public function new() {
		documentChanges = [];
	}

	public function addEdit(edit:EitherType<TextDocumentEdit, EitherType<CreateFile, EitherType<RenameFile, DeleteFile>>>) {
		documentChanges.push(edit);
	}
}

class EditDoc implements refactor.edits.IEditableDocument {
	var list:EditList;
	var fileName:String;
	var edits:Array<TextEdit>;
	var renames:Array<RenameFile>;
	final context:Context;
	final converter:Haxe3DisplayOffsetConverter;

	public function new(fileName:String, list:EditList, context:Context, converter:Haxe3DisplayOffsetConverter) {
		this.fileName = fileName;
		this.list = list;
		this.context = context;
		this.converter = converter;
		edits = [];
		renames = [];
	}

	public function addChange(edit:refactor.edits.FileEdit) {
		switch (edit) {
			case Move(newFileName):
				renames.push({
					kind: RenameFileKind.Kind,
					oldUri: new FsPath(fileName).toUri(),
					newUri: new FsPath(haxe.io.Path.join([Sys.getCwd(), newFileName])).toUri(),
					options: {
						overwrite: false,
						ignoreIfExists: false
					}
				});
			case ReplaceText(text, pos):
				edits.push({range: posToRange(pos), newText: text});
			case InsertText(text, pos):
				edits.push({range: posToRange(pos), newText: text});
			case RemoveText(pos):
				edits.push({range: posToRange(pos), newText: ""});
		}
	}

	function posToRange(pos:refactor.discover.IdentifierPos):Range {
		var doc = context.documents.getHaxe(new FsPath(fileName).toUri());

		if (doc == null) {
			// document currently not loaded -> load and find line number and character pos to build edit Range
			var content:String = sys.io.File.getContent(fileName);
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
				throw '$fileName not found';
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
		list.addEdit({
			textDocument: {
				uri: new FsPath(fileName).toUri(),
				version: null
			},
			edits: edits
		});
		for (rename in renames) {
			list.addEdit(rename);
		}
	}
}
#end

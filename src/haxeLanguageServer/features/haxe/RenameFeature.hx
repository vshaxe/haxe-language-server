package haxeLanguageServer.features.haxe;

import haxe.PosInfos;
import haxe.display.Display.DisplayMethods;
import haxe.display.Display.HoverDisplayItemOccurence;
import haxe.extern.EitherType;
import haxeLanguageServer.protocol.DotPath.getDotPath;
import js.lib.Promise;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import refactor.ITypeList;
import refactor.ITyper;
import refactor.rename.RenameHelper.TypeHintType;

class RenameFeature {
	final context:Context;
	final converter:Haxe3DisplayOffsetConverter;
	final cache:refactor.cache.IFileCache;
	final typer:LanguageServerTyper;

	public function new(context:Context) {
		this.context = context;
		cache = new refactor.cache.MemCache();
		typer = new LanguageServerTyper(context);

		converter = new Haxe3DisplayOffsetConverter();

		context.languageServerProtocol.onRequest(RenameRequest.type, onRename);
	}

	function onRename(params:RenameParams, token:CancellationToken, resolve:WorkspaceEdit->Void, reject:ResponseError<NoData>->Void) {
		final uri = params.textDocument.uri;
		final doc = context.documents.getHaxe(uri);

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
			type: null,
			cache: cache
		};
		typer.typeList = usageContext.typeList;

		// TODO abort if there are unsaved documents (rename operates on fs, so positions might be off)

		// TODO use workspace / compilation server source folders
		var srcFolders:Array<String> = ["src", "Source", "test", "tests"];
		if (context.config.user.renameSourceFolders != null) {
			srcFolders = context.config.user.renameSourceFolders;
		}

		refactor.discover.TraverseSources.traverseSources(srcFolders, usageContext);
		usageContext.usageCollector.updateImportHx(usageContext);
		var editList:EditList = new EditList();

		refactor.Refactor.rename({
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
			verboseLog: function(text:String, ?pos:PosInfos) {
				trace('[rename] $text');
			},
			typer: typer
		}).then((result:refactor.RefactorResult) -> {
			switch (result) {
				case NoChange:
					trace("[rename] no change");
					reject(ResponseError.internalError("no change"));
				case NotFound:
					trace('[rename] could not find identifier at "$fileName@${params.position}"');
					reject(ResponseError.internalError('could not find identifier at "$fileName@${params.position}"'));
				case Unsupported(name):
					trace('[rename] refactoring not supported for "$name"');
					reject(ResponseError.internalError('refactoring not supported for "$name"'));
				case DryRun:
					trace("[rename] dry run");
					reject(ResponseError.internalError("dry run"));
				case Done:
					trace("[rename] successful");
					resolve({documentChanges: editList.documentChanges});
			}
		}).catchError((msg) -> {
			trace('[rename] error: $msg');
			reject(ResponseError.internalError('$msg'));
		});
	}
}

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

class LanguageServerTyper implements ITyper {
	final context:Context;

	public var typeList:Null<ITypeList>;

	public function new(context:Context) {
		this.context = context;
	}

	public function resolveType(fileName:String, pos:Int):Promise<Null<TypeHintType>> {
		final params = {
			file: cast fileName,
			offset: pos,
			wasAutoTriggered: true
		};
		trace('[rename] requesting type info for $fileName@$pos');
		var promise = new Promise(function(resolve:(value:Null<TypeHintType>) -> Void, reject) {
			context.callHaxeMethod(DisplayMethods.Hover, params, null, function(hover) {
				if (hover == null) {
					trace('[rename] received no type info for $fileName@$pos');
					resolve(null);
				} else {
					resolve(buildTypeHint(hover, '$fileName@$pos'));
				}
				return null;
			}, reject.handler());
		});
		return promise;
	}

	function buildTypeHint<T>(item:HoverDisplayItemOccurence<T>, location:String):Null<TypeHintType> {
		if (typeList == null) {
			return null;
		}
		var reg = ~/Class<(.*)>/;

		var type = item!.item!.type;
		if (type == null) {
			return null;
		}
		var path = type!.args!.path;
		if (path == null) {
			return null;
		}
		if (path.moduleName == "StdTypes" && path.typeName == "Null") {
			var params = type!.args!.params;
			if (params == null) {
				return null;
			}
			type = params[0];
			if (type == null) {
				return null;
			}
			path = type!.args!.path;
			if (path == null) {
				return null;
			}
		}
		if (reg.match(path.typeName)) {
			var fullPath = reg.matched(1);
			var parts = fullPath.split(".");
			if (parts.length <= 0) {
				return null;
			}
			@:nullSafety(Off)
			path.typeName = parts.pop();
			path.pack = parts;
		}
		var fullPath = '${getDotPath(type)}';
		trace('[rename] received type $fullPath for $location');
		return typeList.makeTypeHintType(fullPath);
	}
}

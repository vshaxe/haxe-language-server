package haxeLanguageServer.helper;

class WorkspaceEditHelper {
	public static function create(context:Context, params:CodeActionParams, edits:Array<TextEdit>):WorkspaceEdit {
		var doc = context.documents.get(params.textDocument.uri);
		return _create(doc, edits);
	}

	public static function _create(doc:TextDocument, edits:Array<TextEdit>):WorkspaceEdit {
		var changes = new haxe.DynamicAccess<Array<TextEdit>>();
		changes[doc.uri.toString()] = edits;
		return {changes: changes};
	}

	public static function createNewFile(uri:DocumentUri, overwrite:Bool, ignoreIfExists:Bool):CreateFile {
		return {
			kind: CreateFileKind.Create,
			uri: uri,
			options: {
				overwrite: overwrite,
				ignoreIfExists: ignoreIfExists
			}
		}
	}

	public static function textDocumentEdit(uri:DocumentUri, edits:Array<TextEdit>):TextDocumentEdit {
		return {
			textDocument: {
				uri: uri,
				version: null
			},
			edits: edits
		}
	}

	public static function insertText(pos:Position, newText:String):TextEdit {
		return {range: {start: pos, end: pos}, newText: newText};
	}

	public static function replaceText(range:Range, newText:String):TextEdit {
		return {range: range, newText: newText};
	}

	public static function removeText(range:Range):TextEdit {
		return {range: range, newText: ""};
	}
}

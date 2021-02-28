package haxeLanguageServer.helper;

import haxe.DynamicAccess;

class WorkspaceEditHelper {
	overload public static extern inline function create(context:Context, params:CodeActionParams, edits:Array<TextEdit>):WorkspaceEdit {
		final doc = context.documents.getHaxe(params.textDocument.uri);
		return create(doc, edits);
	}

	overload public static extern inline function create(doc:Null<TextDocument>, edits:Array<TextEdit>):WorkspaceEdit {
		final changes = new DynamicAccess<Array<TextEdit>>();
		if (doc != null) {
			changes[doc.uri.toString()] = edits;
		}
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

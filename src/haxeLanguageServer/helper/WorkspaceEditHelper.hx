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
}
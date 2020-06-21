package haxeLanguageServer.documents;

@:allow(haxeLanguageServer.Context)
class TextDocuments {
	public static inline final syncKind = TextDocumentSyncKind.Incremental;

	final context:Context;
	final documents:Map<DocumentUri, TextDocument>;

	public function new(context:Context) {
		this.context = context;
		documents = new Map();
	}

	public inline function iterator():Iterator<TextDocument> {
		return documents.iterator();
	}

	public inline function getHaxe(uri:DocumentUri):Null<HaxeDocument> {
		return Std.downcast(documents[uri], HaxeDocument);
	}

	public inline function getHxml(uri:DocumentUri):Null<HxmlDocument> {
		return Std.downcast(documents[uri], HxmlDocument);
	}

	function onDidOpenTextDocument(event:DidOpenTextDocumentParams) {
		final td = event.textDocument;
		final uri = td.uri;
		if (uri.isHaxeFile()) {
			documents[td.uri] = new HaxeDocument(context, td.uri, td.languageId, td.version, td.text);
		} else if (uri.isHxmlFile()) {
			documents[td.uri] = new HxmlDocument(context, td.uri, td.languageId, td.version, td.text);
		} else {
			throw uri + " has unsupported file type (must be .hx or .hxml)";
		}
	}

	function onDidChangeTextDocument(event:DidChangeTextDocumentParams) {
		final td = event.textDocument;
		final changes = event.contentChanges;
		if (changes.length == 0)
			return;
		final document = documents[td.uri];
		if (document != null) {
			document.update(changes, td.version);
		}
	}

	function onDidCloseTextDocument(event:DidCloseTextDocumentParams) {
		documents.remove(event.textDocument.uri);
	}
}

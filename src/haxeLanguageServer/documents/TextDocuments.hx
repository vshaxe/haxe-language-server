package haxeLanguageServer.documents;

@:allow(haxeLanguageServer.Context)
class TextDocuments {
	public static inline final syncKind = TextDocumentSyncKind.Incremental;

	final documents = new Map<DocumentUri, HxTextDocument>();

	public function new() {}

	public inline function iterator():Iterator<HxTextDocument> {
		return documents.iterator();
	}

	public inline function getHaxe(uri:DocumentUri):Null<HaxeDocument> {
		var doc:Null<HaxeDocument> = Std.downcast(documents[uri], HaxeDocument);
		if (doc == null && uri.isHaxeFile()) {
			// document not opened via client, load it directly from disk
			// see https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didOpen
			doc = new HaxeDocument(uri, "hx", 1, sys.io.File.getContent(uri.toFsPath().toString()));
		}
		return doc;
	}

	public inline function getHxml(uri:DocumentUri):Null<HxmlDocument> {
		var doc:Null<HxmlDocument> = Std.downcast(documents[uri], HxmlDocument);
		if (doc == null && uri.isHxmlFile()) {
			// document not (yet) loaded via client, load it directly from disk
			// see https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didOpen
			doc = new HxmlDocument(uri, "hxml", 1, sys.io.File.getContent(uri.toFsPath().toString()));
		}
		return doc;
	}

	function onDidOpenTextDocument(event:DidOpenTextDocumentParams) {
		final td = event.textDocument;
		final uri = td.uri;
		if (uri.isHaxeFile()) {
			documents[td.uri] = new HaxeDocument(td.uri, td.languageId, td.version, td.text);
		} else if (uri.isHxmlFile()) {
			documents[td.uri] = new HxmlDocument(td.uri, td.languageId, td.version, td.text);
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

package haxeLanguageServer.documents;

@:allow(haxeLanguageServer.Context)
class TextDocuments {
	public static inline var syncKind = TextDocumentSyncKind.Incremental;

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
		final uri = td.uri.toString();
		if (uri.endsWith(".hx")) {
			documents[td.uri] = new HaxeDocument(context, td.uri, td.languageId, td.version, td.text);
		} else if (uri.endsWith(".hxml")) {
			documents[td.uri] = new HxmlDocument(context, td.uri, td.languageId, td.version, td.text);
		} else {
			throw uri + " has unsupported file type (must be .hx or .hxml)";
		}
	}

	function onDidChangeTextDocument(event:DidChangeTextDocumentParams) {
		var td = event.textDocument;
		var changes = event.contentChanges;
		if (changes.length == 0)
			return;
		var document = documents[td.uri];
		if (document != null) {
			document.update(changes, td.version);
		}
	}

	function onDidCloseTextDocument(event:DidCloseTextDocumentParams) {
		documents.remove(event.textDocument.uri);
	}
}

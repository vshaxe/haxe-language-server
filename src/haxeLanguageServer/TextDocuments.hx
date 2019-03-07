package haxeLanguageServer;

import jsonrpc.Protocol;

@:allow(haxeLanguageServer.Context)
class TextDocuments {
	public static inline var syncKind = TextDocumentSyncKind.Incremental;

	final documents:Map<DocumentUri, TextDocument>;

	public function new() {
		documents = new Map();
	}

	public inline function getAll():Iterator<TextDocument> {
		return documents.iterator();
	}

	public inline function get(uri:DocumentUri):TextDocument {
		return documents[uri];
	}

	function onDidOpenTextDocument(event:DidOpenTextDocumentParams) {
		var td = event.textDocument;
		documents[td.uri] = new TextDocument(td.uri, td.languageId, td.version, td.text);
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

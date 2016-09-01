package haxeLanguageServer;

import vscodeProtocol.Protocol;
import vscodeProtocol.Types;

class TextDocuments {
    public static inline var syncKind = TextDocumentSyncKind.Incremental;

    var documents:Map<String,TextDocument>;

    public function new(protocol:Protocol) {
        documents = new Map();
        protocol.onDidChangeTextDocument = onDidChangeTextDocument;
        protocol.onDidCloseTextDocument = onDidCloseTextDocument;
    }

    public inline function getAll():Iterator<TextDocument> {
        return documents.iterator();
    }

    public inline function get(uri:String):TextDocument {
        return documents[uri];
    }

    @:allow(haxeLanguageServer.Context)
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
        if (document != null)
            document.update(changes, td.version);
    }

    function onDidCloseTextDocument(event:DidCloseTextDocumentParams) {
        documents.remove(event.textDocument.uri);
    }
}

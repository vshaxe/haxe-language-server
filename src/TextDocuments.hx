import vscode.Protocol;
import vscode.ProtocolTypes;

class TextDocuments {
    public static inline var syncKind = TextDocumentSyncKind.Incremental;

    var documents:Map<String,TextDocument>;

    public function new(protocol:Protocol) {
        documents = new Map();
        protocol.onDidOpenTextDocument = onDidOpenTextDocument;
        protocol.onDidChangeTextDocument = onDidChangeTextDocument;
        protocol.onDidCloseTextDocument = onDidCloseTextDocument;
        protocol.onDidSaveTextDocument = onDidSaveTextDocument;
    }

    public inline function get(uri:String):TextDocument {
        return documents[uri];
    }

    function onDidOpenTextDocument(event:DidOpenTextDocumentParams) {
        var td = event.textDocument;
        var document = new TextDocument(td.uri, td.languageId, td.version, td.text);
        document.saved = false; // we can't assume the document was unchanged on open
        documents[td.uri] = document;
    }

    function onDidChangeTextDocument(event:DidChangeTextDocumentParams) {
        var td = event.textDocument;
        var changes = event.contentChanges;
        if (changes.length == 0)
            return;
        var document = documents[td.uri];
        if (document != null) {
            document.update(changes, td.version);
            document.saved = false;
        }
    }

    function onDidCloseTextDocument(event:DidCloseTextDocumentParams) {
        documents.remove(event.textDocument.uri);
    }

    function onDidSaveTextDocument(event:DidSaveTextDocumentParams) {
        var document = documents[event.textDocument.uri];
        if (document != null)
            document.saved = true;
    }
}

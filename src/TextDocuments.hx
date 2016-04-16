import vscode.Protocol;
import vscode.ProtocolTypes;

class TextDocuments {
    var documents:Map<String,TextDocument>;

    public static inline var syncKind = TextDocumentSyncKind.Incremental;

    public function new() {
        documents = new Map();
    }

    public inline function get(uri:String):TextDocument {
        return documents[uri];
    }

    public function listen(protocol:Protocol):Void {
        protocol.onDidOpenTextDocument = function(event) {
            var td = event.textDocument;
            var document = new TextDocument(td.uri, td.languageId, td.version, td.text);
            document.saved = false; // we can't assume the document was unchanged on open
            documents[td.uri] = document;
        };
        protocol.onDidChangeTextDocument = function(event) {
            var td = event.textDocument;
            var changes = event.contentChanges;
            if (changes.length == 0)
                return;
            var document = documents[td.uri];
            if (document != null) {
                document.update(changes, td.version);
                document.saved = false;
            }
        };
        protocol.onDidCloseTextDocument = function(event) {
            documents.remove(event.textDocument.uri);
        };
        protocol.onDidSaveTextDocument = function(event) {
            var document = documents[event.textDocument.uri];
            if (document != null)
                document.saved = true;
        };
    }
}

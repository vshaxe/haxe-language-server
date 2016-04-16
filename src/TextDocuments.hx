import vscode.Protocol;

class TextDocuments {
    var documents:Map<String,TextDocument>;

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
            document.saved = true;
            documents[td.uri] = document;
        };
        protocol.onDidChangeTextDocument = function(event) {
            var td = event.textDocument;
            var changes = event.contentChanges;
            var last = changes.length > 0 ? changes[changes.length - 1] : null;
            if (last != null) {
                var document = documents[td.uri];
                if (document != null) {
                    document.update(last, td.version);
                    document.saved = false;
                }
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

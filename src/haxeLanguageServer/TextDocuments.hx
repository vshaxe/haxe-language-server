package haxeLanguageServer;

import jsonrpc.Protocol;

class TextDocuments {
    public static inline var syncKind = TextDocumentSyncKind.Incremental;

    var protocol:Protocol;
    var documents:Map<DocumentUri,TextDocument>;

    public function new(protocol:Protocol) {
        this.protocol = protocol;
        documents = new Map();
        protocol.onNotification(Methods.DidChangeTextDocument, onDidChangeTextDocument);
        protocol.onNotification(Methods.DidCloseTextDocument, onDidCloseTextDocument);
    }

    public inline function getAll():Iterator<TextDocument> {
        return documents.iterator();
    }

    public inline function get(uri:DocumentUri):TextDocument {
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
        if (document != null) {
            document.update(changes, td.version);
            #if false
            protocol.sendNotification(VshaxeMethods.UpdateParseTree, {uri: td.uri.toString(), parseTree: haxe.Serializer.run(document.parsingInfo.tree)});
            #end
        }
    }

    function onDidCloseTextDocument(event:DidCloseTextDocumentParams) {
        documents.remove(event.textDocument.uri);
    }
}

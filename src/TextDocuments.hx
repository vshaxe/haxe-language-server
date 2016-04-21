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

    // todo: handle unsaved documents
    public function haxePositionToRange(pos:HaxePosition, cache:Map<String,Array<String>>):vscode.BasicTypes.Range {
        var startLine = if (pos.startLine != null) pos.startLine - 1 else pos.line - 1;
        var endLine = if (pos.endLine != null) pos.endLine - 1 else pos.line - 1;
        var startChar = 0;
        var endChar = 0;

        // if we have byte offsets within line, we need to convert them to character offsets
        // for that we have to read the file :-/
        #if haxe_languageserver_no_utf8_char_pos
        if (pos.startByte != null)
            startChar = pos.startByte;
        if (pos.endByte != null)
            endChar = pos.endByte;
        #else
        var lines = null;
        inline function getLineChar(line:Int, byteOffset:Int):Int {
            if (lines == null) {
                if (cache == null) {
                    lines = sys.io.File.getContent(pos.file).split("\n");
                } else {
                    lines = cache[pos.file];
                    if (lines == null)
                        lines = cache[pos.file] = sys.io.File.getContent(pos.file).split("\n");
                }
            }
            var lineContent = new js.node.Buffer(lines[line], "utf-8");
            var lineTextSlice = lineContent.toString("utf-8", 0, byteOffset);
            return lineTextSlice.length;
        }
        if (pos.startByte != null && pos.startByte != 0)
            startChar = getLineChar(startLine, pos.startByte);
        if (pos.endByte != null && pos.endByte != 0)
            endChar = getLineChar(endLine, pos.endByte);
        #end

        return {
            start: {line: startLine, character: startChar},
            end: {line: endLine, character: endChar},
        };
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

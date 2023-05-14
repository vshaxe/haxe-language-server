import haxeLanguageServer.Context;
import haxeLanguageServer.documents.HaxeDocument;
import haxeLanguageServer.features.haxe.DiagnosticsFeature;
import haxeLanguageServer.features.haxe.GotoDefinitionFeature;
import haxeLanguageServer.helper.DisplayOffsetConverter;
import haxeLanguageServer.helper.SemVer;
import jsonrpc.Protocol;
import languageServerProtocol.textdocument.TextDocument;

using StringTools;

@:access(haxeLanguageServer.documents.TextDocuments)
@:access(haxeLanguageServer.Context)
@:access(haxeLanguageServer.server.HaxeServer)
class DisplayTestContext {
	var markers:Map<Int, Int>;
	var fieldName:String;

	public final context:Context;
	public final uri:DocumentUri;
	public final doc:HaxeDocument;
	public final result:Null<String>;

	public function new(path:String, fieldName:String, sources:Array<String>, markers:Map<Int, Int>) {
		this.fieldName = fieldName;
		this.markers = markers;

		context = new Context(new Protocol((msg, token) -> {}));
		uri = new DocumentUri("file://" + fieldName + ".codeActionTest");
		doc = new HaxeDocument(uri, "haxe", 4, sources[0]);
		result = sources[1];

		// some hacks to make tests works
		context.haxeServer.haxeVersion = new SemVer(4, 3, 0);
		context.haxeServer.supportedMethods = ["display/definition"];
		context.capabilities ??= {};

		final docs = context.documents.documents;
		docs[uri] = new HaxeDocument(uri, "hx", 1, doc.content);

		context.gotoDefinition = new GotoDefinitionFeature(context);
		context.displayOffsetConverter = DisplayOffsetConverter.create(context.haxeServer.haxeVersion);
	}

	public function pos(id:Int):Position {
		final off = markers[id] ?? throw "No such marker: " + id;
		return doc.positionAt(off);
	}

	public function range(id:Int, id2:Int):Range {
		return {
			start: pos(id),
			end: pos(id2)
		};
	}

	public function rangeText(id:Int, id2:Int):String {
		return doc.getText(range(id, id2));
	}

	public function createDiagnostic(range:Range, msg:String):Diagnostic {
		return {
			range: range,
			message: msg
		};
	}

	public function codeActionParams(range:Range):CodeActionParams {
		return {
			textDocument: {uri: uri},
			range: range,
			context: {
				diagnostics: []
			}
		};
	}

	public function applyTextEdit(edit:WorkspaceEdit):Void {
		var hasChange = false;
		final changes = edit.documentChanges;
		var newContent = doc.content;
		if ((changes is Array)) {
			for (change in changes) {
				final change:TextDocumentEdit = cast change;
				newContent = applyEdits(newContent, change.edits);
				hasChange = true;
			}
			doc.content = newContent;
		}

		final changes = edit.changes;
		for (edits in changes) {
			newContent = applyEdits(newContent, edits);
			hasChange = true;
			doc.content = newContent;
		}
	}

	function applyEdits(before:String, edits:Array<TextEdit>):String {
		edits.sort((a, b) -> {
			if (a.range.start.line == b.range.start.line) {
				return a.range.start.character - b.range.start.character;
			}
			return a.range.start.line - b.range.start.line;
		});
		var currentDoc = "";
		var offset = 0;
		for (edit in edits) {
			final startOffset = doc.offsetAt(edit.range.start);
			currentDoc += before.substr(offset, startOffset - offset) + edit.newText;
			offset = doc.offsetAt(edit.range.end);
		}
		return currentDoc + before.substr(offset);
	}
}

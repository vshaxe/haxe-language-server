package haxeLanguageServer.features;

import formatter.Formatter;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

class DocumentFormattingFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.languageServerProtocol.onRequest(DocumentFormattingRequest.type, onDocumentFormatting);
	}

	function onDocumentFormatting(params:DocumentFormattingParams, token:CancellationToken, resolve:Array<TextEdit>->Void,
			reject:ResponseError<NoData>->Void) {
		var onResolve = context.startTimer("haxe/formatting");
		var uri = params.textDocument.uri;
		var doc:Null<TextDocument> = context.documents.get(uri);
		if (doc == null) {
			return reject.documentNotFound(uri);
		}
		var tokens = doc.tokens;
		if (tokens == null) {
			return reject.noTokens();
		}

		var config = Formatter.loadConfig(if (doc.uri.isFile()) {
			doc.uri.toFsPath().toString();
		} else {
			context.workspacePath.toString();
		});
		var result = Formatter.format(Tokens(tokens.list, tokens.tree, tokens.bytes), config);
		switch result {
			case Success(formattedCode):
				var fullRange = {
					start: {line: 0, character: 0},
					end: {line: doc.lineCount - 1, character: doc.lineAt(doc.lineCount - 1).length}
				}
				var edits = [{range: fullRange, newText: formattedCode}];
				resolve(edits);
				onResolve();
			case Failure(errorMessage):
				reject(ResponseError.internalError(errorMessage));
			case Disabled:
				reject(ResponseError.internalError("Formatting is disabled for this file"));
		}
	}
}

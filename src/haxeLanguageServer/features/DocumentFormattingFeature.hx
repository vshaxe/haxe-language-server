package haxeLanguageServer.features;

import formatter.Formatter;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

class DocumentFormattingFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.protocol.onRequest(Methods.DocumentFormatting, onDocumentFormatting);
	}

	function onDocumentFormatting(params:DocumentFormattingParams, token:CancellationToken, resolve:Array<TextEdit>->Void,
			reject:ResponseError<NoData>->Void) {
		var onResolve = context.startTimer(Methods.DocumentFormatting);
		var doc = context.documents.get(params.textDocument.uri);
		if (doc.tokens == null) {
			return reject.noTokens();
		}
		var formatter = new Formatter();
		var result = formatter.formatFile({
			name: if (doc.uri.isFile()) {
				doc.uri.toFsPath().toString();
			} else {
				context.workspacePath + "/untitled.hx";
			},
			content: doc.tokens.bytes
		}, {
			tokens: doc.tokens.list,
			tokenTree: doc.tokens.tree
		});
		switch (result) {
			case Success(formattedCode):
				var fullRange = {
					start: {line: 0, character: 0},
					end: {line: doc.lineCount - 1, character: doc.lineAt(doc.lineCount - 1).length}
				}
				var edits = [{range: fullRange, newText: formattedCode}];
				resolve(edits);
				onResolve(edits);
			case Failure(errorMessage):
				reject(ResponseError.internalError(errorMessage));
			case Disabled:
				reject(ResponseError.internalError("Formatting is disabled for this file"));
		}
	}
}

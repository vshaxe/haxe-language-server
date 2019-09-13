package haxeLanguageServer.features;

import formatter.Formatter;
import formatter.codedata.FormatterInputData.FormatterInputRange;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import haxeLanguageServer.helper.DisplayOffsetConverter;

class DocumentFormattingFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.languageServerProtocol.onRequest(DocumentFormattingRequest.type, onDocumentFormatting);
		context.languageServerProtocol.onRequest(DocumentRangeFormattingRequest.type, onDocumentRangeFormatting);
	}

	function onDocumentFormatting(params:DocumentFormattingParams, token:CancellationToken, resolve:Array<TextEdit>->Void,
			reject:ResponseError<NoData>->Void) {
		format(params.textDocument.uri, null, resolve, reject);
	}

	function onDocumentRangeFormatting(params:DocumentRangeFormattingParams, token:CancellationToken, resolve:Array<TextEdit>->Void,
			reject:ResponseError<NoData>->Void) {
		format(params.textDocument.uri, params.range, resolve, reject);
	}

	function format(uri:DocumentUri, range:Null<Range>, resolve:Array<TextEdit>->Void, reject:ResponseError<NoData>->Void) {
		var onResolve = context.startTimer("haxe/formatting");
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
		var inputRange:FormatterInputRange = null;
		if (range != null) {
			range.start.character = 0;
			var converter = new Haxe3DisplayOffsetConverter();
			function convert(position) {
				return converter.characterOffsetToByteOffset(doc.content, doc.offsetAt(position));
			}
			inputRange = {
				startPos: convert(range.start),
				endPos: convert(range.end)
			}
		}
		var result = Formatter.format(Tokens(tokens.list, tokens.tree, tokens.bytes), config, inputRange);
		switch result {
			case Success(formattedCode):
				if (range == null) {
					range = {
						start: {line: 0, character: 0},
						end: {line: doc.lineCount - 1, character: doc.lineAt(doc.lineCount - 1).length}
					}
				}
				var edits = [{range: range, newText: formattedCode}];
				resolve(edits);
				onResolve();
			case Failure(errorMessage):
				reject(ResponseError.internalError(errorMessage));
			case Disabled:
				reject(ResponseError.internalError("Formatting is disabled for this file"));
		}
	}
}

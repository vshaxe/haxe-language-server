package haxeLanguageServer.features.haxe;

import formatter.Formatter;
import formatter.codedata.FormatterInputData.FormatterInputRange;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

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
		final onResolve = context.startTimer("textDocument/formatting");
		final doc:Null<HaxeDocument> = context.documents.getHaxe(uri);
		if (doc == null) {
			return reject.noFittingDocument(uri);
		}
		final tokens = doc.tokens;
		if (tokens == null) {
			return reject.noTokens();
		}

		var path;
		var origin;
		if (doc.uri.isFile()) {
			path = doc.uri.toFsPath().toString();
			origin = SourceFile(path);
		} else {
			path = context.workspacePath.toString();
			origin = Snippet;
		}
		final config = Formatter.loadConfig(path);
		var inputRange:Null<FormatterInputRange> = null;
		if (range != null) {
			range.start.character = 0;
			final converter = new Haxe3DisplayOffsetConverter();
			function convert(position) {
				return converter.characterOffsetToByteOffset(doc.content, doc.offsetAt(position));
			}
			inputRange = {
				startPos: convert(range.start),
				endPos: convert(range.end)
			}
		}
		final result = Formatter.format(Tokens(tokens.list, tokens.tree, tokens.bytes, origin), config, inputRange);
		switch result {
			case Success(formattedCode):
				final range:Range = if (range == null) {
					{
						start: {line: 0, character: 0},
						end: {line: doc.lineCount - 1, character: doc.lineAt(doc.lineCount - 1).length}
					}
				} else {
					range;
				}
				if (doc.getText(range) != formattedCode) {
					final edits = [{range: range, newText: formattedCode}];
					resolve(edits);
					onResolve(null, edits.length + " changes");
				}
			case Failure(errorMessage):
				reject(ResponseError.internalError(errorMessage));
			case Disabled:
				reject(ResponseError.internalError("Formatting is disabled for this file"));
		}
	}
}

package haxeLanguageServer.tokentree;

import haxe.Json;
import haxe.PosInfos;
import haxeLanguageServer.documents.HaxeDocument;
import haxeLanguageServer.features.haxe.documentSymbols.DocumentSymbolsResolver;
import haxeLanguageServer.features.haxe.foldingRange.FoldingRangeResolver;

class TokenTreeTest extends Test {
	function testDocumentSymbols() {
		compareOutput("cases/documentSymbols", document -> {
			return new DocumentSymbolsResolver(document).resolve();
		});
	}

	function testFoldingRange() {
		compareOutput("cases/foldingRange", document -> {
			return new FoldingRangeResolver(document, {foldingRange: {lineFoldingOnly: false}}).resolve();
		});
	}

	function compareOutput(basePath:String, resolve:(document:HaxeDocument) -> Dynamic, ?pos:PosInfos) {
		final inputPath = '$basePath/Input.hx';

		var content = sys.io.File.getContent(inputPath);
		content = content.replace("\r", "");
		final uri = new FsPath(inputPath).toUri();
		final document = new HaxeDocument(uri, "haxe", 0, content);

		final stringify = Json.stringify.bind(_, null, "\t");
		final actual = stringify(resolve(document));
		sys.io.File.saveContent('$basePath/Actual.json', actual);
		final expected = stringify(Json.parse(sys.io.File.getContent('$basePath/Expected.json')));

		// use "Compare Active File With..." and select Actual.json and Expected.json for debugging
		Assert.equals(expected, actual, pos);
	}
}

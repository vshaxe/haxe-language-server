package haxeLanguageServer.tokentree;

import haxe.Json;
import haxeLanguageServer.TextDocument;

class TokenTreeTest extends TestCaseBase {
    function testDocumentSymbols() {
        compareOutput("cases/documentSymbols", document -> {
            return new DocumentSymbolsResolver(document, true).resolve();
        });
    }

    function testFoldingRange() {
        compareOutput("cases/foldingRange", document -> {
            return new FoldingRangeResolver(document, {foldingRange: {lineFoldingOnly: false}}).resolve();
        });
    }

    function compareOutput(basePath:String, resolve:(document:TextDocument)->Dynamic) {
        var inputPath = '$basePath/Input.hx';

        var content = sys.io.File.getContent(inputPath);
        content = content.replace("\r", "");
        var uri = new FsPath(inputPath).toUri();
        var document = new TextDocument(uri, "haxe", 0, content);

        var stringify = Json.stringify.bind(_, null, "    ");
        var actual = stringify(resolve(document));
        sys.io.File.saveContent('$basePath/Actual.json', actual);
        var expected = stringify(Json.parse(sys.io.File.getContent('$basePath/Expected.json')));

        // use "Compare Active File With..." and select Actual.json and Expected.json for debugging
        assertTrue(actual == expected);
    }
}

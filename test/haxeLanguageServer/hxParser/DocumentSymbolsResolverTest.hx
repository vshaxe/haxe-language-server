package haxeLanguageServer.hxParser;

import haxe.Json;
import haxeLanguageServer.TextDocument;

class DocumentSymbolsResolverTest extends TestCaseBase {
    /* function test() {
        var basePath = "cases/documentSymbols";
        var inputPath = '$basePath/Input.hx';

        var content = sys.io.File.getContent(inputPath);
        var uri = new FsPath(inputPath).toUri();
        var document = new TextDocument(uri, "haxe", 0, content);
        var resolver = new DocumentSymbolsResolver(uri);
        resolver.walkFile(document.parseTree, Root);

        var stringify = Json.stringify.bind(_, null, "    ");
        var actual = stringify(resolver.getSymbols());
        sys.io.File.saveContent('$basePath/Actual.json', actual);
        var expected = stringify(Json.parse(sys.io.File.getContent('$basePath/Expected.json')));

        // use "Compare Active File With..." and select Actual.json and Expected.json for debugging
        assertTrue(actual == expected);
    } */
}
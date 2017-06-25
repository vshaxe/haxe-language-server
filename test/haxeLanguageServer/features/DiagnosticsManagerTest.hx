package haxeLanguageServer.features;

import mockatoo.Mockatoo.*;
import jsonrpc.Protocol;
import haxeLanguageServer.TextDocument;
import haxeLanguageServer.TextDocuments;
import haxeLanguageServer.helper.DisplayOffsetConverter;
import languageServerProtocol.Types;
using mockatoo.Mockatoo;

class DiagnosticsManagerTest extends TestCaseBase {
    function runTest(errbackMsg:String, expectedFile:FsPath, expectedDiagnostics:Array<Diagnostic>, pathFilter:String, ?c:haxe.PosInfos) {
        var protocol = mock(Protocol);
        var context = mock(Context);
        var documents = mock(TextDocuments);
        var document = mock(TextDocument);
        documents.get(cast any).returns(document);
        context.protocol.returns(protocol);
        context.documents.returns(documents);
        context.config.returns({
            diagnosticsPathFilter: pathFilter
        });
        context.workspacePath.returns("");
        context.callDisplay(cast any, cast any, cast any, cast any, cast any).calls(function(args) {
            var errback:String->Void = args[4];
            errback(errbackMsg);
        });
        context.displayOffsetConverter.returns(new Haxe4DisplayOffsetConverter());

        var called = false;
        var expectedUri = expectedFile.toUri();
        protocol.sendNotification(Methods.PublishDiagnostics, cast any).calls(function(args) {
            called = true;
            var result:PublishDiagnosticsParams = args[1];
            assertEquals(expectedUri, result.uri, c);
            assertEquals(expectedDiagnostics.length, result.diagnostics.length, c);
            for (i in 0...result.diagnostics.length) {
                var expected = expectedDiagnostics[i];
                var actual = result.diagnostics[i];
                assertTrue(expected.range.isEqual(actual.range), c);
                assertEquals(expected.message, actual.message, c);
                assertEquals("haxe", actual.source, c);
            }
        });

        var manager = new DiagnosticsManager(context);
        manager.publishDiagnostics(expectedUri);
        assertEquals(expectedDiagnostics.length > 0, called, c);
    }

    function runTestCase(testCase:TestCase, pathFilter:String, ?c:haxe.PosInfos) {
        runTest(testCase.errback, testCase.file, testCase.results, pathFilter, c);
    }

    function testSimpleErrbackDiagnostic() {
        runTestCase(TestCases.UnexpectedImport, "");
    }

    function testMatchingPathFilter() {
        runTestCase(TestCases.UnexpectedImport, "C:/Lib/");
    }

    function testNonMatchingPathFilter() {
        var test:TestCase = TestCases.UnexpectedImport;
        runTest(test.errback, test.file, [], "X:/No/Match");
    }
}


private typedef TestCase = {
    errback:String,
    file:FsPath,
    results:Array<Diagnostic>
}


private class TestCases {
    public static var UnexpectedImport:TestCase = {
        errback: "C:/Lib/File.hx:4: characters 1-7 : Unexpected import",
        file: new FsPath("C:/Lib/File.hx"),
        results: [{
            range: {start: {character: 0, line: 3}, end: {character: 6, line: 3}},
            message: "Unexpected import"
        }]
    };
}
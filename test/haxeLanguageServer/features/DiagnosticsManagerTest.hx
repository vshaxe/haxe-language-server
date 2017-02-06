package haxeLanguageServer.features;

import mockatoo.Mockatoo.*;
import jsonrpc.Protocol;
import haxeLanguageServer.Uri;
import haxeLanguageServer.TextDocuments;
import haxeLanguageServer.TextDocument;
import languageServerProtocol.Types;
using mockatoo.Mockatoo;

class DiagnosticsManagerTest extends TestCaseBase {
    function runTest(errbackMsg:String, expectedUri:String, expectedDiagnostics:Array<Diagnostic>) {
        var protocol = mock(Protocol);
        var context = mock(Context);
        var documents = mock(TextDocuments);
        var document = mock(TextDocument);
        documents.get(cast any).returns(document);
        context.protocol.returns(protocol);
        context.documents.returns(documents);
        context.config.returns({
            diagnosticsPathFilter: ""
        });
        context.workspacePath.returns("");
        context.callDisplay(cast any, cast any, cast any, cast any, cast any).calls(function(args) {
            var errback:String->Void = args[4];
            errback(errbackMsg);
        });
        protocol.sendNotification(Methods.PublishDiagnostics, cast any).calls(function(args) {
            var result:PublishDiagnosticsParams = args[1];
            assertEquals(expectedUri, result.uri);
            assertEquals(expectedDiagnostics.length, result.diagnostics.length);
            for (i in 0...result.diagnostics.length) {
                var expected = expectedDiagnostics[i];
                var actual = result.diagnostics[i];
                assertTrue(expected.range.isEqual(actual.range));
                assertEquals(expected.message, actual.message);
                assertEquals("haxe", actual.source);
            }
        });

        var manager = new DiagnosticsManager(context);
        manager.publishDiagnostics(expectedUri);
    }

    function testSimpleErrbackDiagnostic() {
        runTest("C:/Lib/File.hx:4: characters 0-6 : Unexpected import", Uri.fsPathToUri("C:/Lib/File.hx"), [{
            range: {start: {character: 0, line: 3}, end: {character: 6, line: 3}},
            message: "Unexpected import"
        }]);
    }
}
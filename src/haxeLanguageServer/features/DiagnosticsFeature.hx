package haxeLanguageServer.features;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import vscodeProtocol.Types;

using StringTools;

@:enum abstract UnresolvedIdentifierSuggestion(Int) {
    var UISImport = 0;
    var UISTypo = 1;

    public inline function new(i:Int) {
        this = i;
    }
}

@:enum abstract DiagnosticsKind<T>(Int) from Int to Int {
    var DKUnusedImport:DiagnosticsKind<Void> = 0;
    var DKUnresolvedIdentifier:DiagnosticsKind<Array<{kind: UnresolvedIdentifierSuggestion, name: String}>> = 1;
    var DKCompilerError:DiagnosticsKind<String> = 2;

    public inline function new(i:Int) {
        this = i;
    }

    public function getMessage(args:T) {
        return switch ((this : DiagnosticsKind<T>)) {
            case DKUnusedImport: "Unused import";
            case DKUnresolvedIdentifier: "Unresolved identifier";
            case DKCompilerError: args;
        }
    }
}

typedef HaxeDiagnostics<T> = {
    var kind:DiagnosticsKind<T>;
    var range:Range;
    var severity:DiagnosticSeverity;
    var args:T;
}

typedef DiagnosticsMapKey = {code: Int, range:Range};

class DiagnosticsMap<T> extends haxe.ds.BalancedTree<DiagnosticsMapKey, T> {
    override function compare(k1:DiagnosticsMapKey, k2:DiagnosticsMapKey) {
        var start1 = k1.range.start;
        var start2 = k2.range.start;
        var end1 = k1.range.end;
        var end2 = k2.range.end;
        inline function compare(i1, i2, e) return i1 < i2 ? -1 : i1 > i2 ? 1 : e;
        return compare(k1.code, k2.code, compare(start1.line, start2.line, compare(start1.character, start2.character,
            compare(end1.line, end2.line, compare(end1.character, end2.character, 0)
        ))));
    }
}

class DiagnosticsFeature extends Feature {

    var diagnosticsArguments:DiagnosticsMap<Dynamic>;

    public function new(context:Context) {
        super(context);
        context.protocol.onCodeAction = onCodeAction;
        diagnosticsArguments = new DiagnosticsMap();
    }

    public function getDiagnostics(uri:String) {
        var doc = context.documents.get(uri);
        function processReply(s:String) {
            diagnosticsArguments = new DiagnosticsMap();
            var data:Array<HaxeDiagnostics<Dynamic>> =
                try haxe.Json.parse(s)
                catch (e:Dynamic) {
                    trace("Error parsing diagnostics response: " + e);
                    return;
                }

            var diagnostics = new Array<Diagnostic>();
            for (hxDiag in data) {
                if (hxDiag.range == null)
                    continue;
                var diag:Diagnostic = {
                    range: doc.byteRangeToRange(hxDiag.range),
                    source: "haxe",
                    code: (hxDiag.kind : Int),
                    severity: hxDiag.severity,
                    message: hxDiag.kind.getMessage(hxDiag.args)
                }
                diagnosticsArguments.set({code: diag.code, range: diag.range}, hxDiag.args);
                diagnostics.push(diag);
            }

            context.protocol.sendPublishDiagnostics({uri: uri, diagnostics: diagnostics});
        }
        function processError(error:String) {
            context.protocol.sendLogMessage({type: Error, message: error});
        }
        callDisplay(["--display", doc.fsPath + "@0@diagnostics"], null, null, processReply, processError);
    }

    function getDiagnosticsArguments<T>(kind:DiagnosticsKind<T>, range:Range):T {
        return diagnosticsArguments.get({code: kind, range: range});
    }

    function onCodeAction<T>(params:CodeActionParams, token:CancellationToken, resolve:Array<Command> -> Void, reject:ResponseError<NoData> -> Void) {
        var ret:Array<Command> = [];
        for (d in params.context.diagnostics) {
            if (!(d.code is Int)) // our codes are int, so we don't handle other stuff
                continue;
            var code = new DiagnosticsKind<T>(d.code);
            switch (code) {
                case DKUnusedImport:
                    ret.push({
                        title: "Remove import",
                        command: "haxe.applyFixes",
                        arguments: [params.textDocument.uri, 0 /*TODO*/, [{range: d.range, newText: ""}]]
                    });
                case DKUnresolvedIdentifier:
                    var args = getDiagnosticsArguments(code, d.range);
                    for (arg in args) {
                        var kind = new UnresolvedIdentifierSuggestion(d.code);
                        var command:Command = switch (kind) {
                            case UISImport: {
                                title: "import " + arg.name,
                                command: "haxe.applyFixes", // TODO
                                arguments: []
                            }
                            case UISTypo: {
                                title: "Change to " +arg.name,
                                command: "haxe.applyFixes",
                                arguments: [params.textDocument.uri, 0, [{range: d.range, newText: arg.name}]]
                            }
                        }
                        ret.push(command);
                    }
                case DKCompilerError:
                    var arg = getDiagnosticsArguments(code, d.range);
                    var sugrex = ~/\(Suggestions?: (.*)\)/;
                    if (sugrex.match(arg)) {
                        var suggestions = sugrex.matched(1).split(",");
                        // Haxe reports the entire expression, not just the field position, so we have to be a bit creative here.
                        var range = d.range;
                        var fieldrex = ~/has no field ([^ ]+) /;
                        if (fieldrex.match(arg)) {
                            var fieldName = fieldrex.matched(1);
                            range.start.character += range.end.character - fieldrex.matched(1).length - 2;
                        }
                        for (suggestion in suggestions) {
                            suggestion = suggestion.trim();
                            ret.push({
                                title: "Change to " + suggestion,
                                command: "haxe.applyFixes",
                                arguments: [params.textDocument.uri, 0, [{range: range, newText: suggestion}]]
                            });
                        }
                    }
            }
        }
        resolve(ret);
    }
}
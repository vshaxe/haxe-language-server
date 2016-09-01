package haxeLanguageServer.features;

import vscodeProtocol.Types;
using StringTools;

class DiagnosticsManager {
    var context:Context;
    var diagnosticsArguments:DiagnosticsMap<Any>;

    public function new(context:Context) {
        this.context = context;
        diagnosticsArguments = new DiagnosticsMap();
        context.protocol.onNotification(VshaxeMethods.RunGlobalDiagnostics, onRunGlobalDiagnostics);
    }

    function onRunGlobalDiagnostics(s:String) {
        function processError(error:String) {
            context.protocol.sendLogMessage({type: Error, message: error});
        }
        context.callDisplay(["--display", "diagnostics"], null, null, processDiagnosticsReply, processError);
    }

    function sendDiagnostics(uri: String, hxDiagnostics:Array<HaxeDiagnostics<Any>>) {
        // var doc = context.documents.get(uri);
        // if (doc == null) {
        //     return;
        // }
        var diagnostics = new Array<Diagnostic>();
        for (hxDiag in hxDiagnostics) {
            if (hxDiag.range == null)
                continue;
            var diag:Diagnostic = {
                // range: doc.byteRangeToRange(hxDiag.range),
                range: hxDiag.range,
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

    function processDiagnosticsReply(s:String) {
        diagnosticsArguments = new DiagnosticsMap();
        var data:Array<HaxeDiagnosticsResponse<Any>> =
            try haxe.Json.parse(s)
            catch (e:Any) {
                trace("Error parsing diagnostics response: " + Std.string(e));
                return;
            }
        var workspaceUri = Uri.fsPathToUri(context.workspacePath);
        for (data in data) {
            var uri = Uri.fsPathToUri(data.file);
            if (uri.startsWith(workspaceUri)) {
                sendDiagnostics(uri, data.diagnostics);
            }
        }
    }

    public function publishDiagnostics(uri:String) {
        function processError(error:String) {
            context.protocol.sendLogMessage({type: Error, message: error});
        }
        var doc = context.documents.get(uri);
        context.callDisplay(["--display", doc.fsPath + "@0@diagnostics"], null, null, processDiagnosticsReply, processError);
    }

    static var reEndsWithWhitespace = ~/\s*$/;
    static var reStartsWhitespace = ~/^\s*/;

    public function addCodeActions<T>(params:CodeActionParams, actions:Array<Command>) {
        for (d in params.context.diagnostics) {
            if (!(d.code is Int)) // our codes are int, so we don't handle other stuff
                continue;
            var code = new DiagnosticsKind<T>(d.code);
            switch (code) {
                case DKUnusedImport:
                    var doc = context.documents.get(params.textDocument.uri);
                    var range = d.range;

                    var startLine = doc.lineAt(range.start.line);
                    if (reStartsWhitespace.match(startLine.substring(0, range.start.character)))
                        range = {
                            start: {
                                line: range.start.line,
                                character: 0
                            },
                            end: range.end
                        };

                    var endLine = if (range.start.line == range.end.line) startLine else doc.lineAt(range.end.line);
                    if (reEndsWithWhitespace.match(endLine.substring(range.end.character)))
                        range = {
                            start: range.start,
                            end: {
                                line: range.end.line + 1,
                                character: 0
                            }
                        };

                    actions.push({
                        title: "Remove import",
                        command: "haxe.applyFixes",
                        arguments: [params.textDocument.uri, 0 /*TODO*/, [{range: range, newText: ""}]]
                    });
                case DKUnresolvedIdentifier:
                    var args = getDiagnosticsArguments(code, d.range);
                    for (arg in args) {
                        var commands:Array<Command> = switch (arg.kind) {
                            case UISImport:
                                [{
                                    title: "import " + arg.name,
                                    command: "haxe.applyFixes", // TODO
                                    arguments: []
                                }, {
                                    title: "Change to " + arg.name,
                                    command: "haxe.applyFixes",
                                    arguments: [params.textDocument.uri, 0, [{range: d.range, newText: arg.name}]]
                                }];
                            case UISTypo:
                                [{
                                    title: "Change to " +arg.name,
                                    command: "haxe.applyFixes",
                                    arguments: [params.textDocument.uri, 0, [{range: d.range, newText: arg.name}]]
                                }];
                        }
                        for (command in commands) {
                            actions.push(command);
                        }
                    }
                case DKCompilerError:
                    var arg = getDiagnosticsArguments(code, d.range)[0];
                    var sugrex = ~/\(Suggestions?: (.*)\)/;
                    if (sugrex.match(arg)) {
                        var suggestions = sugrex.matched(1).split(",");
                        // Haxe reports the entire expression, not just the field position, so we have to be a bit creative here.
                        var range = d.range;
                        var fieldrex = ~/has no field ([^ ]+) /;
                        if (fieldrex.match(arg)) {
                            range.start.character += range.end.character - fieldrex.matched(1).length - 2;
                        }
                        for (suggestion in suggestions) {
                            suggestion = suggestion.trim();
                            actions.push({
                                title: "Change to " + suggestion,
                                command: "haxe.applyFixes",
                                arguments: [params.textDocument.uri, 0, [{range: range, newText: suggestion}]]
                            });
                        }
                    }
            }
        }
    }

    inline function getDiagnosticsArguments<T>(kind:DiagnosticsKind<T>, range:Range):T {
        return diagnosticsArguments.get({code: kind, range: range});
    }
}


@:enum private abstract UnresolvedIdentifierSuggestion(Int) {
    var UISImport = 0;
    var UISTypo = 1;

    public inline function new(i:Int) {
        this = i;
    }
}


@:enum private abstract DiagnosticsKind<T>(Int) from Int to Int {
    var DKUnusedImport:DiagnosticsKind<Void> = 0;
    var DKUnresolvedIdentifier:DiagnosticsKind<Array<{kind: UnresolvedIdentifierSuggestion, name: String}>> = 1;
    var DKCompilerError:DiagnosticsKind<Array<String>> = 2;

    public inline function new(i:Int) {
        this = i;
    }

    public function getMessage(args:T) {
        return switch ((this : DiagnosticsKind<T>)) {
            case DKUnusedImport: "Unused import";
            case DKUnresolvedIdentifier: "Unresolved identifier";
            case DKCompilerError: args[0];
        }
    }
}

private typedef HaxeDiagnostics<T> = {
    var kind:DiagnosticsKind<T>;
    var range:Range;
    var severity:DiagnosticSeverity;
    var args:T;
}

private typedef HaxeDiagnosticsResponse<T> = {
    var file:String;
    var diagnostics:Array<HaxeDiagnostics<T>>;
}

private typedef DiagnosticsMapKey = {code: Int, range:Range};

private class DiagnosticsMap<T> extends haxe.ds.BalancedTree<DiagnosticsMapKey, T> {
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

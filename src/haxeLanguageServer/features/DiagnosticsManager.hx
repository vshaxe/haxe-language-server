package haxeLanguageServer.features;

import haxe.io.Path;
import haxeLanguageServer.helper.PathHelper;
import haxeLanguageServer.helper.ImportHelper;
import haxeLanguageServer.HaxeServer.DisplayResult;
import js.node.ChildProcess;

class DiagnosticsManager {
    var context:Context;
    var diagnosticsArguments:Map<DocumentUri,DiagnosticsMap<Any>>;
    var haxelibPath:FsPath;

    public function new(context:Context) {
        this.context = context;
        context.registerCodeActionContributor(getCodeActions);
        diagnosticsArguments = new Map();
        context.protocol.onNotification(VshaxeMethods.RunGlobalDiagnostics, onRunGlobalDiagnostics);
        ChildProcess.exec("haxelib config", function(error, stdout, stderr) haxelibPath = new FsPath(stdout.trim()));
    }

    function onRunGlobalDiagnostics(_) {
        var stopProgress = context.startProgress("collecting diagnostics");
        context.callDisplay(["--display", "diagnostics"], null, null, function(result) {
            processDiagnosticsReply(null, result);
            stopProgress();
        }, function(error) {
            processErrorReply(null, error);
            stopProgress();
        });
    }

    function processErrorReply(uri:Null<DocumentUri>, error:String) {
        if (!extractDiagnosticsFromHaxeError(uri, error))
            clearDiagnostics(uri);
        context.sendLogMessage(Log, error);
    }

    function extractDiagnosticsFromHaxeError(uri:Null<DocumentUri>, error:String):Bool {
        var problemMatcher = ~/(.+):(\d+): (?:lines \d+-(\d+)|character(?:s (\d+)-| )(\d+)) : (?:(Warning) : )?(.*)/;
        if (!problemMatcher.match(error))
            return false;

        var file = problemMatcher.matched(1);
        if (!Path.isAbsolute(file))
            file = Path.join([Sys.getCwd(), file]);

        var targetUri = new FsPath(file).toUri();
        if (targetUri != uri)
            return false; // only allow error reply diagnostics in current file for now (clearing becomes annoying otherwise...)

        if (isPathFiltered(targetUri.toFsPath()))
            return false;

        inline function getInt(i)
            return Std.parseInt(problemMatcher.matched(i));

        var line = getInt(2);
        var endLine = getInt(3);
        var column = getInt(4);
        var endColumn = getInt(5);

        if (endLine == null) endLine = line;
        var position = {line: line - 1, character: column};
        var endPosition = {line: endLine - 1, character: endColumn};

        var argumentsMap = diagnosticsArguments[uri] = new DiagnosticsMap();
        var diag = {
            range: {start: position, end: endPosition},
            source: "haxe",
            severity: Error,
            message: problemMatcher.matched(7)
        };
        context.protocol.sendNotification(Methods.PublishDiagnostics, {uri: uri, diagnostics: [diag]});
        argumentsMap.set({code: DKCompilerError, range: diag.range}, error);
        return true;
    }

    function processDiagnosticsReply(uri:Null<DocumentUri>, r:DisplayResult) {
        switch (r) {
            case DCancelled:
                // nothing to do \o/
            case DResult(s):
                var data:Array<HaxeDiagnosticsResponse<Any>> =
                    try haxe.Json.parse(s)
                    catch (e:Any) {
                        trace("Error parsing diagnostics response: " + Std.string(e));
                        return;
                    }

                var sent = new Map<DocumentUri,Bool>();
                for (data in data) {
                    if (isPathFiltered(data.file))
                        continue;

                    var uri = data.file.toUri();
                    var argumentsMap = diagnosticsArguments[uri] = new DiagnosticsMap();

                    var diagnostics = new Array<Diagnostic>();
                    for (hxDiag in data.diagnostics) {
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
                        argumentsMap.set({code: diag.code, range: diag.range}, hxDiag.args);
                        diagnostics.push(diag);
                    }
                    context.protocol.sendNotification(Methods.PublishDiagnostics, {uri: uri, diagnostics: diagnostics});
                    sent[uri] = true;
                }

                inline function removeOldDiagnostics(uri:DocumentUri) {
                    if (!sent.exists(uri)) clearDiagnostics(uri);
                }

                if (uri == null) {
                    for (uri in diagnosticsArguments.keys())
                        removeOldDiagnostics(uri);
                } else {
                    removeOldDiagnostics(uri);
                }
        }
    }

    function isPathFiltered(path:FsPath):Bool {
        var pathFilter = PathHelper.preparePathFilter(context.config.diagnosticsPathFilter, haxelibPath, context.workspacePath);
        return !PathHelper.matches(path, pathFilter);
    }

    inline function clearDiagnostics(uri:DocumentUri) {
        if (diagnosticsArguments.remove(uri))
            context.protocol.sendNotification(Methods.PublishDiagnostics, {uri: uri, diagnostics: []});
    }

    public function publishDiagnostics(uri:DocumentUri) {
        if (isPathFiltered(uri.toFsPath())) {
            clearDiagnostics(uri);
            return;
        }
        var doc = context.documents.get(uri);
        context.callDisplay(["--display", doc.fsPath + "@0@diagnostics"], null, null, processDiagnosticsReply.bind(uri), processErrorReply.bind(uri));
    }

    static var reEndsWithWhitespace = ~/\s*$/;
    static var reStartsWhitespace = ~/^\s*/;

    function getCodeActions<T>(params:CodeActionParams) {
        var actions:Array<Command> = [];
        for (d in params.context.diagnostics) {
            if (!(d.code is Int)) // our codes are int, so we don't handle other stuff
                continue;
            var code = new DiagnosticsKind<T>(d.code);
            actions = actions.concat(switch (code) {
                case DKUnusedImport: getUnusedImportActions(params, d);
                case DKUnresolvedIdentifier: getUnresolvedIdentifierActions(params, d);
                case DKCompilerError: getCompilerErrorActions(params, d);
                case DKRemovableCode: getRemovableCodeActions(params, d);
            });
        }
        return actions;
    }

    function getUnusedImportActions(params:CodeActionParams, d:Diagnostic):Array<Command> {
        var doc = context.documents.get(params.textDocument.uri);

        function patchRange(range:Range) {
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
            return range;
        }

        var ret:Array<Command> = new ApplyFixesCommand("Remove unused import/using", params,
            [{range: patchRange(d.range), newText: ""}]);

        var map = diagnosticsArguments[params.textDocument.uri];
        if (map != null) {
            var fixes = [
                for (key in map.keys())
                    if (key.code == DKUnusedImport)
                        {range: patchRange(key.range), newText: ""}
            ];

            if (fixes.length > 1) {
                ret.unshift(new ApplyFixesCommand("Remove all unused imports/usings", params, fixes));
            }
        }

        return ret;
    }

    function getUnresolvedIdentifierActions(params:CodeActionParams, d:Diagnostic):Array<Command> {
        var actions:Array<Command> = [];
        var args = getDiagnosticsArguments(params.textDocument.uri, DKUnresolvedIdentifier, d.range);
        for (arg in args) {
            actions = actions.concat(switch (arg.kind) {
                case UISImport: getUnresolvedImportActions(params, d, arg);
                case UISTypo: getTypoActions(params, d, arg);
            });
        }
        return actions;
    }

    function getUnresolvedImportActions(params:CodeActionParams, d:Diagnostic, arg):Array<Command> {
        var doc = context.documents.get(params.textDocument.uri);
        var importPos = ImportHelper.getImportInsertPosition(doc);
        var importRange = { start: importPos, end: importPos };
        return [
            new ApplyFixesCommand("Import " + arg.name, params,
                [{range: importRange, newText: 'import ${arg.name};\n'}]
            ),
            new ApplyFixesCommand("Change to " + arg.name, params,
                [{range: d.range, newText: arg.name}]
            )
        ];
    }

    function getTypoActions(params:CodeActionParams, d:Diagnostic, arg):Array<Command> {
        return new ApplyFixesCommand("Change to " + arg.name, params,
            [{range: d.range, newText: arg.name}]);
    }

    function getCompilerErrorActions(params:CodeActionParams, d:Diagnostic):Array<Command> {
        var actions:Array<Command> = [];
        var arg = getDiagnosticsArguments(params.textDocument.uri, DKCompilerError, d.range);
        var suggestionsRe = ~/\(Suggestions?: (.*)\)/;
        if (suggestionsRe.match(arg)) {
            var suggestions = suggestionsRe.matched(1).split(",");
            // Haxe reports the entire expression, not just the field position, so we have to be a bit creative here.
            var range = d.range;
            var fieldRe = ~/has no field ([^ ]+) /;
            if (fieldRe.match(arg)) {
                range.start.character += range.end.character - fieldRe.matched(1).length - 2;
            }
            for (suggestion in suggestions) {
                suggestion = suggestion.trim();
                actions.push(new ApplyFixesCommand("Change to " + suggestion, params,
                    [{range: range, newText: suggestion}]));
            }
            return actions;
        }

        var invalidPackageRe = ~/Invalid package : ([\w.]*) should be ([\w.]*)/;
        if (invalidPackageRe.match(arg)) {
            var is = invalidPackageRe.matched(1);
            var shouldBe = invalidPackageRe.matched(2);
            var text = context.documents.get(params.textDocument.uri).getText(d.range);
            var replacement = text.replace(is, shouldBe);
            actions.push(new ApplyFixesCommand("Change to " + replacement, params, [{range: d.range, newText: replacement}]));
        }
        return actions;
    }

    function getRemovableCodeActions(params:CodeActionParams, d:Diagnostic):Array<Command> {
        var range = getDiagnosticsArguments(params.textDocument.uri, DKRemovableCode, d.range).range;
        if (range == null) return [];
        return new ApplyFixesCommand("Remove", params, [{range: range, newText: ""}]);
    }

    inline function getDiagnosticsArguments<T>(uri:DocumentUri, kind:DiagnosticsKind<T>, range:Range):T {
        var map = diagnosticsArguments[uri];
        if (map == null) return null;
        return map.get({code: kind, range: range});
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
    var DKCompilerError:DiagnosticsKind<String> = 2;
    var DKRemovableCode:DiagnosticsKind<{description:String, range:Range}> = 3;

    public inline function new(i:Int) {
        this = i;
    }

    public function getMessage(args:T) {
        return switch ((this : DiagnosticsKind<T>)) {
            case DKUnusedImport: "Unused import/using";
            case DKUnresolvedIdentifier: "Unresolved identifier";
            case DKCompilerError: args;
            case DKRemovableCode: args.description;
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
    var file:FsPath;
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

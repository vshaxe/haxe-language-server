package haxeLanguageServer.features;

import haxe.io.Path;
import haxeLanguageServer.helper.PathHelper;
import haxeLanguageServer.helper.ImportHelper;
import haxeLanguageServer.server.DisplayResult;
import haxeLanguageServer.helper.WorkspaceEditHelper;
import haxeLanguageServer.LanguageServerMethods;
import js.node.ChildProcess;
using Lambda;

class DiagnosticsManager {
    static inline var DiagnosticsSource = "diagnostics";
    static inline var RemoveUnusedImportUsingTitle = "Remove unused import/using";

    final context:Context;
    final diagnosticsArguments:Map<DocumentUri,DiagnosticsMap<Any>>;
    final errorUri:DocumentUri;
    var haxelibPath:FsPath;

    public function new(context:Context) {
        this.context = context;
        context.registerCodeActionContributor(getCodeActions);
        diagnosticsArguments = new Map();
        errorUri = new FsPath(Path.join([context.workspacePath.toString(), "Error"])).toUri();
        context.protocol.onNotification(LanguageServerMethods.RunGlobalDiagnostics, onRunGlobalDiagnostics);
        ChildProcess.exec("haxelib config", (error, stdout, stderr) -> haxelibPath = new FsPath(stdout.trim()));
    }

    function onRunGlobalDiagnostics(_) {
        var stopProgress = context.startProgress("Collecting Diagnostics");
        context.callDisplay("global diagnostics", ["diagnostics"], null, null, function(result) {
            processDiagnosticsReply(null, result);
            context.protocol.sendNotification(LanguageServerMethods.DidRunRunGlobalDiagnostics);
            stopProgress();
        }, function(error) {
            processErrorReply(null, error);
            stopProgress();
        });
    }

    function processErrorReply(uri:Null<DocumentUri>, error:String) {
        if (!extractDiagnosticsFromHaxeError(uri, error) && !extractDiagnosticsFromHaxeError2(error)) {
            clearDiagnostics(uri);
            clearDiagnostics(errorUri);
        }
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

        function makePosition(line:Int, character:Int) {
            return {
                line: line - 1,
                character: context.displayOffsetConverter.positionCharToZeroBasedColumn(character)
            }
        }

        if (endLine == null) endLine = line;
        var position = makePosition(line, column);
        var endPosition = makePosition(endLine, endColumn);

        var diag = {
            range: {start: position, end: endPosition},
            source: DiagnosticsSource,
            severity: DiagnosticSeverity.Error,
            message: problemMatcher.matched(7)
        };
        publishDiagnostic(uri, diag, error);
        return true;
    }

    function extractDiagnosticsFromHaxeError2(error:String):Bool {
        var problemMatcher = ~/^(Error): (.*)$/;
        if (!problemMatcher.match(error)) {
            return false;
        }

        var diag = {
            range: {start: {line: 0, character: 0}, end: {line: 0, character: 0}},
            source: DiagnosticsSource,
            severity: DiagnosticSeverity.Error,
            message: problemMatcher.matched(2)
        };
        publishDiagnostic(errorUri, diag, error);
        return true;
    }

    function publishDiagnostic(uri:DocumentUri, diag:Diagnostic, error:String) {
        context.protocol.sendNotification(Methods.PublishDiagnostics, {uri: uri, diagnostics: [diag]});
        var argumentsMap = diagnosticsArguments[uri] = new DiagnosticsMap();
        argumentsMap.set({code: DKCompilerError, range: diag.range}, error);
    }

    function processDiagnosticsReply(uri:Null<DocumentUri>, r:DisplayResult) {
        clearDiagnostics(errorUri);
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
                        var kind:Int = hxDiag.kind;
                        var diag:Diagnostic = {
                            // range: doc.byteRangeToRange(hxDiag.range),
                            range: hxDiag.range,
                            source: DiagnosticsSource,
                            code: kind,
                            severity: hxDiag.severity,
                            message: hxDiag.kind.getMessage(hxDiag.args)
                        }
                        if (kind == DKRemovableCode || kind == DKUnusedImport || diag.message.indexOf("has no effect") != -1) {
                            diag.severity = Hint;
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

    public function clearDiagnostics(uri:DocumentUri) {
        if (diagnosticsArguments.remove(uri))
            context.protocol.sendNotification(Methods.PublishDiagnostics, {uri: uri, diagnostics: []});
    }

    public function publishDiagnostics(uri:DocumentUri) {
        if (isPathFiltered(uri.toFsPath())) {
            clearDiagnostics(uri);
            return;
        }
        var doc = context.documents.get(uri);
        if (doc != null) {
            context.callDisplay("@diagnostics", [doc.fsPath + "@0@diagnostics"], null, null, processDiagnosticsReply.bind(uri), processErrorReply.bind(uri));
        }
    }

    static final reEndsWithWhitespace = ~/\s*$/;
    static final reStartsWhitespace = ~/^\s*/;

    function getCodeActions<T>(params:CodeActionParams) {
        var actions:Array<CodeAction> = [];
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
        actions = actions.concat(getSourceActions(params, actions));
        return actions;
    }

    function getUnusedImportActions(params:CodeActionParams, d:Diagnostic):Array<CodeAction> {
        var doc = context.documents.get(params.textDocument.uri);
        return [{
            title: RemoveUnusedImportUsingTitle,
            edit: WorkspaceEditHelper.create(context, params, [{range: patchRange(doc, d.range), newText: ""}]),
            diagnostics: [d]
        }];
    }

    function getUnresolvedIdentifierActions(params:CodeActionParams, d:Diagnostic):Array<CodeAction> {
        var actions:Array<CodeAction> = [];
        var args = getDiagnosticsArguments(params.textDocument.uri, DKUnresolvedIdentifier, d.range);
        for (arg in args) {
            actions = actions.concat(switch (arg.kind) {
                case UISImport: getUnresolvedImportActions(params, d, arg);
                case UISTypo: getTypoActions(params, d, arg);
            });
        }
        return actions;
    }

    function getUnresolvedImportActions(params:CodeActionParams, d:Diagnostic, arg):Array<CodeAction> {
        var doc = context.documents.get(params.textDocument.uri);
        var importStyle = context.config.codeGeneration.imports.style;
        return [
            {
                title: "Import " + arg.name,
                kind: QuickFix,
                edit: WorkspaceEditHelper.create(context, params,
                    [ImportHelper.createImportsEdit(doc, ImportHelper.getImportPosition(doc), [arg.name], importStyle)]),
                diagnostics: [d]
            },
            {
                title: "Change to " + arg.name,
                kind: QuickFix,
                edit: WorkspaceEditHelper.create(context, params, [{range: d.range, newText: arg.name}]),
                diagnostics: [d]
            }
        ];
    }

    function getTypoActions(params:CodeActionParams, d:Diagnostic, arg):Array<CodeAction> {
        return [{
            title: "Change to " + arg.name,
            kind: QuickFix,
            edit: WorkspaceEditHelper.create(context, params, [{range: d.range, newText: arg.name}]),
            diagnostics: [d]
        }];
    }

    function getCompilerErrorActions(params:CodeActionParams, d:Diagnostic):Array<CodeAction> {
        var actions:Array<CodeAction> = [];
        var arg = getDiagnosticsArguments(params.textDocument.uri, DKCompilerError, d.range);
        var suggestionsRe = ~/\(Suggestions?: (.*)\)/;
        if (suggestionsRe.match(arg)) {
            var suggestions = suggestionsRe.matched(1).split(",");
            // Haxe reports the entire expression, not just the field position, so we have to be a bit creative here.
            var range = d.range;
            var fieldRe = ~/has no field ([^ ]+) /;
            if (fieldRe.match(arg)) {
                range.start.character = range.end.character - fieldRe.matched(1).length;
            }
            for (suggestion in suggestions) {
                suggestion = suggestion.trim();
                actions.push({
                    title: "Change to " + suggestion,
                    kind: QuickFix,
                    edit: WorkspaceEditHelper.create(context, params, [{range: range, newText: suggestion}]),
                    diagnostics: [d]
                });
            }
            return actions;
        }

        var invalidPackageRe = ~/Invalid package : ([\w.]*) should be ([\w.]*)/;
        if (invalidPackageRe.match(arg)) {
            var is = invalidPackageRe.matched(1);
            var shouldBe = invalidPackageRe.matched(2);
            var text = context.documents.get(params.textDocument.uri).getText(d.range);
            var replacement = text.replace(is, shouldBe);
            actions.push({
                title: "Change to " + replacement,
                kind: QuickFix,
                edit: WorkspaceEditHelper.create(context, params, [{range: d.range, newText: replacement}]),
                diagnostics: [d]
            });
        }

        return actions;
    }

    function getRemovableCodeActions(params:CodeActionParams, d:Diagnostic):Array<CodeAction> {
        var range = getDiagnosticsArguments(params.textDocument.uri, DKRemovableCode, d.range).range;
        if (range == null) return [];
        return [{
            title: "Remove",
            edit: WorkspaceEditHelper.create(context, params, [{range: range, newText: ""}]),
            diagnostics: [d]
        }];
    }

    function getSourceActions(params:CodeActionParams, existingActions:Array<CodeAction>):Array<CodeAction> {
        var map = diagnosticsArguments[params.textDocument.uri];
        if (map == null) {
            return [];
        }

        var doc = context.documents.get(params.textDocument.uri);
        var fixes = [
            for (key in map.keys())
                if (key.code == DKUnusedImport)
                    {range: patchRange(doc, key.range), newText: ""}
        ];

        var diagnostics = existingActions.filter(action -> action.title == RemoveUnusedImportUsingTitle)
            .map(action -> action.diagnostics).flatten().array();
        var actions = [];
        if (fixes.length > 1) {
            existingActions.unshift({
                title: "Remove all unused imports/usings",
                edit: WorkspaceEditHelper.create(context, params, fixes),
                diagnostics: diagnostics
            });
        }
        return actions;
    }

    function patchRange(doc:TextDocument, range:Range) {
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

    inline function getDiagnosticsArguments<T>(uri:DocumentUri, kind:DiagnosticsKind<T>, range:Range):T {
        var map = diagnosticsArguments[uri];
        if (map == null) return null;
        return map.get({code: kind, range: range});
    }
}


private enum abstract UnresolvedIdentifierSuggestion(Int) {
    var UISImport;
    var UISTypo;

    public inline function new(i:Int) {
        this = i;
    }
}


private enum abstract DiagnosticsKind<T>(Int) from Int to Int {
    var DKUnusedImport:DiagnosticsKind<Void>;
    var DKUnresolvedIdentifier:DiagnosticsKind<Array<{kind: UnresolvedIdentifierSuggestion, name: String}>>;
    var DKCompilerError:DiagnosticsKind<String>;
    var DKRemovableCode:DiagnosticsKind<{description:String, range:Range}>;

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

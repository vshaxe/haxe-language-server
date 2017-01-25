package haxeLanguageServer.features;

import haxeLanguageServer.helper.PathHelper;
import haxeLanguageServer.helper.ImportHelper;
import languageServerProtocol.Types;
import js.node.ChildProcess;

class DiagnosticsManager {
    var context:Context;
    var diagnosticsArguments:Map<String,DiagnosticsMap>;
    var additionalDiagnostics:Map<String,DiagnosticsMap>;
    var haxelibPath:String;

    public function new(context:Context) {
        this.context = context;
        diagnosticsArguments = new Map();
        additionalDiagnostics = new Map();
        context.protocol.onNotification(VshaxeMethods.RunGlobalDiagnostics, onRunGlobalDiagnostics);
        ChildProcess.exec("haxelib config", function(error, stdout, stderr) haxelibPath = stdout.trim());
    }

    function onRunGlobalDiagnostics(_) {
        context.callDisplay(["--display", "diagnostics"], null, null, processDiagnosticsReply.bind(null), processErrorReply);
    }

    function processErrorReply(error:String) {
        context.sendLogMessage(Log, error);
    }

    function processDiagnosticsReply(uri:Null<String>, s:String) {
        var data:Array<HaxeDiagnosticsResponse<Any>> =
            try haxe.Json.parse(s)
            catch (e:Any) {
                trace("Error parsing diagnostics response: " + Std.string(e));
                return;
            }

        var pathFilter = PathHelper.preparePathFilter(context.config.diagnosticsPathFilter, haxelibPath, context.workspacePath);
        var sent = new Map<String,Bool>();
        for (data in data) {
            if (PathHelper.matches(data.file, pathFilter)) {
                var uri = Uri.fsPathToUri(data.file);
                var argumentsMap = diagnosticsArguments[uri] = new DiagnosticsMap();
                // var doc = context.documents.get(uri);
                // if (doc == null) {
                //     return;
                // }
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
                    argumentsMap.set({code: diag.code, range: diag.range}, {args: hxDiag.args, diagnostic: diag});
                }
                publishDiagnostics(uri);
                sent[uri] = true;
            }
        }

        inline function removeOldDiagnostsics(uri:String) {
            if (!sent.exists(uri)) clearDiagnostics(uri);
        }

        if (uri == null) {
            for (uri in diagnosticsArguments.keys())
                removeOldDiagnostsics(uri);
        } else {
            removeOldDiagnostsics(uri);
        }
    }

    public function addAdditionalDiagnostic(uri:String, diagnostic:Diagnostic, command:Command) {
        var map = additionalDiagnostics[uri] = new DiagnosticsMap();
        map.add(DKCustom, diagnostic, command);
        publishDiagnostics(uri);
    }

    public function clearAdditionalDiagnostics() {
        var uris = [for (uri in additionalDiagnostics.keys()) uri];
        additionalDiagnostics = new Map();
        for (uri in uris) publishDiagnostics(uri);
    }

    function publishDiagnostics(uri:String) {
        function getDiagnostics(uri, map) {
            var map = map.get(uri);
            if (map == null) return [];
            return map.getDiagnostics();
        }
        var diagnostics = getDiagnostics(uri, diagnosticsArguments).concat(getDiagnostics(uri, additionalDiagnostics));
        context.protocol.sendNotification(Methods.PublishDiagnostics, {uri: uri, diagnostics: diagnostics});
    }

    inline function clearDiagnostics(uri:String) {
        if (diagnosticsArguments.remove(uri))
            context.protocol.sendNotification(Methods.PublishDiagnostics, {uri: uri, diagnostics: []});
    }

    public function refreshDiagnostics(uri:String) {
        var doc = context.documents.get(uri);
        context.callDisplay(["--display", doc.fsPath + "@0@diagnostics"], null, null, processDiagnosticsReply.bind(uri), processErrorReply);
    }

    static var reEndsWithWhitespace = ~/\s*$/;
    static var reStartsWhitespace = ~/^\s*/;

    public function getCodeActions<T>(params:CodeActionParams) {
        var actions:Array<Command> = [];
        for (d in params.context.diagnostics) {
            if (!(d.code is Int)) // our codes are int, so we don't handle other stuff
                continue;
            var code = new DiagnosticsKind<T>(d.code);
            actions = actions.concat(switch (code) {
                case DKCustom: [getDiagnosticsArguments(additionalDiagnostics, params.textDocument.uri, DKCustom, params.range)];
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

        var ret:Array<Command> = [{
            title: "Remove unused import/using",
            command: "haxe.applyFixes",
            arguments: [params.textDocument.uri, 0 /*TODO*/, [{range: patchRange(d.range), newText: ""}]]
        }];

        var map = diagnosticsArguments[params.textDocument.uri];
        if (map != null) {
            var fixes = [
                for (key in map.keys())
                    if (key.code == DKUnusedImport)
                        {range: patchRange(key.range), newText: ""}
            ];

            if (fixes.length > 1) {
                ret.unshift({
                    title: "Remove all unused imports/usings",
                    command: "haxe.applyFixes",
                    arguments: [params.textDocument.uri, 0, fixes]
                });
            }
        }

        return ret;
    }

    function getUnresolvedIdentifierActions(params:CodeActionParams, d:Diagnostic):Array<Command> {
        var actions:Array<Command> = [];
        var args = getDiagnosticsArguments(diagnosticsArguments, params.textDocument.uri, DKUnresolvedIdentifier, d.range);
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
        return [{
            title: "Import " + arg.name,
            command: "haxe.applyFixes",
            arguments: [params.textDocument.uri, 0, [{range: importRange, newText: 'import ${arg.name};\n'}]]
        }, {
            title: "Change to " + arg.name,
            command: "haxe.applyFixes",
            arguments: [params.textDocument.uri, 0, [{range: d.range, newText: arg.name}]]
        }];
    }

    function getTypoActions(params:CodeActionParams, d:Diagnostic, arg):Array<Command> {
        return [{
            title: "Change to " + arg.name,
            command: "haxe.applyFixes",
            arguments: [params.textDocument.uri, 0, [{range: d.range, newText: arg.name}]]
        }];
    }

    function getCompilerErrorActions(params:CodeActionParams, d:Diagnostic):Array<Command> {
        var actions:Array<Command> = [];
        var arg = getDiagnosticsArguments(diagnosticsArguments, params.textDocument.uri, DKCompilerError, d.range);
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
        return actions;
    }

    function getRemovableCodeActions(params:CodeActionParams, d:Diagnostic):Array<Command> {
        var range = getDiagnosticsArguments(diagnosticsArguments, params.textDocument.uri, DKRemovableCode, d.range).range;
        if (range == null) {
            return [];
        }
        return [{
            title: "Remove",
            command: "haxe.applyFixes",
            arguments: [params.textDocument.uri, 0, [{range: range, newText: ""}]]
        }];
    }

    inline function getDiagnosticsArguments<T>(map:Map<String,DiagnosticsMap>, uri:String, kind:DiagnosticsKind<T>, range:Range):T {
        var map = map[uri];
        if (map == null) return null;
        return map.get({code: kind, range: range}).args;
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
    var DKCustom:DiagnosticsKind<Command> = -1; // 
    var DKUnusedImport:DiagnosticsKind<Void> = 0;
    var DKUnresolvedIdentifier:DiagnosticsKind<Array<{kind: UnresolvedIdentifierSuggestion, name: String}>> = 1;
    var DKCompilerError:DiagnosticsKind<String> = 2;
    var DKRemovableCode:DiagnosticsKind<{description:String, range:Range}> = 3;

    public inline function new(i:Int) {
        this = i;
    }

    public function getMessage(args:T) {
        return switch ((this : DiagnosticsKind<T>)) {
            case DKCustom: args.title;
            case DKUnusedImport: "Unused import";
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
    var file:String;
    var diagnostics:Array<HaxeDiagnostics<T>>;
}

private typedef DiagnosticsMapKey = {code:Int, range:Range};

private typedef DiagnosticsMapValue = {args:Any, diagnostic:Diagnostic};

private class DiagnosticsMap extends haxe.ds.BalancedTree<DiagnosticsMapKey, DiagnosticsMapValue> {
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

    public function add(code:Int, diagnostic:Diagnostic, args:Any) {
        set({code: code, range: diagnostic.range}, {args: args, diagnostic: diagnostic});
    }

    public function getDiagnostics():Array<Diagnostic> {
        return [for (value in this) value.diagnostic];
    }
}

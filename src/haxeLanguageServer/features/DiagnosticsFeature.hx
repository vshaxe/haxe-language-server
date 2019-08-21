package haxeLanguageServer.features;

import haxe.Json;
import haxe.io.Path;
import haxeLanguageServer.helper.TypeHelper;
import haxeLanguageServer.Configuration;
import haxeLanguageServer.helper.PathHelper;
import haxeLanguageServer.helper.ImportHelper;
import haxeLanguageServer.server.DisplayResult;
import haxeLanguageServer.helper.WorkspaceEditHelper;
import haxeLanguageServer.LanguageServerMethods;
import js.node.ChildProcess;

using Lambda;

class DiagnosticsFeature {
	static inline var DiagnosticsSource = "diagnostics";
	static inline var RemoveUnusedImportUsingTitle = "Remove unused import/using";
	static inline var RemoveAllUnusedImportsUsingsTitle = "Remove all unused imports/usings";

	final context:Context;
	final tagSupport:Bool;
	final diagnosticsArguments:Map<DocumentUri, DiagnosticsMap<Any>>;
	final errorUri:DocumentUri;

	var haxelibPath:Null<FsPath>;

	public function new(context:Context) {
		this.context = context;
		tagSupport = context.capabilities.textDocument!.publishDiagnostics!.tagSupport == true;
		diagnosticsArguments = new Map();
		errorUri = new FsPath(Path.join([context.workspacePath.toString(), "Error"])).toUri();

		ChildProcess.exec(context.config.haxelib.executable + " config", (error, stdout, stderr) -> haxelibPath = new FsPath(stdout.trim()));

		context.registerCodeActionContributor(getCodeActions);
		context.languageServerProtocol.onNotification(LanguageServerMethods.RunGlobalDiagnostics, onRunGlobalDiagnostics);
	}

	function onRunGlobalDiagnostics(_) {
		var stopProgress = context.startProgress("Collecting Diagnostics");
		var onResolve = context.startTimer("@diagnostics");

		context.callDisplay("global diagnostics", ["diagnostics"], null, null, function(result) {
			processDiagnosticsReply(null, onResolve, result);
			context.languageServerProtocol.sendNotification(LanguageServerMethods.DidRunRunGlobalDiagnostics);
			stopProgress();
		}, function(error) {
			processErrorReply(null, error);
			stopProgress();
		});
	}

	function processErrorReply(uri:Null<DocumentUri>, error:String) {
		if (!extractDiagnosticsFromHaxeError(uri, error) && !extractDiagnosticsFromHaxeError2(error)) {
			if (uri != null) {
				clearDiagnostics(uri);
			}
			clearDiagnostics(errorUri);
		}
		trace(error);
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

		if (endLine == null)
			endLine = line;
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
		context.languageServerProtocol.sendNotification(Methods.PublishDiagnostics, {uri: uri, diagnostics: [diag]});
		var argumentsMap = diagnosticsArguments[uri] = new DiagnosticsMap();
		argumentsMap.set({code: CompilerError, range: diag.range}, error);
	}

	function processDiagnosticsReply(uri:Null<DocumentUri>, onResolve:(result:Dynamic, ?debugInfo:String) -> Void, r:DisplayResult) {
		clearDiagnostics(errorUri);
		switch (r) {
			case DCancelled:
			// nothing to do \o/
			case DResult(s):
				var data:Array<HaxeDiagnosticResponse<Any>> = try haxe.Json.parse(s) catch (e:Any) {
					trace("Error parsing diagnostics response: " + Std.string(e));
					return;
				}

				var count = 0;
				var sent = new Map<DocumentUri, Bool>();
				for (data in data) {
					count += data.diagnostics.length;

					var file = data.file;
					if (data.file == null) {
						// LSP always needs a URI for now (https://github.com/Microsoft/language-server-protocol/issues/256)
						file = errorUri.toFsPath();
					}
					if (isPathFiltered(file))
						continue;

					var uri = file.toUri();
					var argumentsMap = diagnosticsArguments[uri] = new DiagnosticsMap();

					var newDiagnostics = filterRelevantDiagnostics(data.diagnostics);
					var diagnostics = new Array<Diagnostic>();
					for (hxDiag in newDiagnostics) {
						var range = hxDiag.range;
						if (hxDiag.range == null) {
							// range is not optional in the LSP yet
							range = {
								start: {line: 0, character: 0},
								end: {line: 0, character: 0}
							}
						}

						var kind:Int = hxDiag.kind;
						var diag:Diagnostic = {
							range: range,
							source: DiagnosticsSource,
							code: kind,
							severity: hxDiag.severity,
							message: hxDiag.kind.getMessage(hxDiag.args)
						}
						if (kind == RemovableCode
							|| kind == UnusedImport
							|| diag.message.contains("has no effect")
							|| kind == InactiveBlock) {
							diag.severity = Hint;
							diag.tags = [Unnecessary];
						}
						argumentsMap.set({code: kind, range: diag.range}, hxDiag.args);
						diagnostics.push(diag);
					}
					context.languageServerProtocol.sendNotification(Methods.PublishDiagnostics, {uri: uri, diagnostics: diagnostics});
					sent[uri] = true;
				}

				inline function removeOldDiagnostics(uri:DocumentUri) {
					if (!sent.exists(uri))
						clearDiagnostics(uri);
				}

				if (uri == null) {
					for (uri in diagnosticsArguments.keys())
						removeOldDiagnostics(uri);
				} else {
					removeOldDiagnostics(uri);
				}

				onResolve(data, count + " diagnostics");
		}
	}

	function isPathFiltered(path:FsPath):Bool {
		var pathFilter = PathHelper.preparePathFilter(context.config.user.diagnosticsPathFilter, haxelibPath, context.workspacePath);
		return !PathHelper.matches(path, pathFilter);
	}

	function filterRelevantDiagnostics(diagnostics:Array<HaxeDiagnostic<Any>>):Array<HaxeDiagnostic<Any>> {
		// hide regular compiler errors while there's parser errors, they can be misleading
		var hasProblematicParserErrors = diagnostics.find(d -> switch (d.kind : Int) {
			case ParserError: d.args != "Missing ;"; // don't be too strict
			case _: false;
		}) != null;
		if (hasProblematicParserErrors) {
			diagnostics = diagnostics.filter(d -> switch (d.kind : Int) {
				case CompilerError, UnresolvedIdentifier: false;
				case _: true;
			});
		}

		// hide unused import warnings while there's compiler errors (to avoid false positives)
		var hasCompilerErrors = diagnostics.find(d -> d.kind == cast CompilerError) != null;
		if (hasCompilerErrors) {
			diagnostics = diagnostics.filter(d -> d.kind != cast UnusedImport);
		}

		return diagnostics;
	}

	public function clearDiagnostics(uri:DocumentUri) {
		if (diagnosticsArguments.remove(uri))
			context.languageServerProtocol.sendNotification(Methods.PublishDiagnostics, {uri: uri, diagnostics: []});
	}

	public function publishDiagnostics(uri:DocumentUri) {
		if (!uri.isFile() || isPathFiltered(uri.toFsPath())) {
			clearDiagnostics(uri);
			return;
		}
		var doc:Null<TextDocument> = context.documents.get(uri);
		if (doc != null) {
			var onResolve = context.startTimer("@diagnostics");
			context.callDisplay("@diagnostics", [doc.uri.toFsPath() + "@0@diagnostics"], null, null, processDiagnosticsReply.bind(uri, onResolve),
				processErrorReply.bind(uri));
		}
	}

	static final reEndsWithWhitespace = ~/\s*$/;
	static final reStartsWhitespace = ~/^\s*/;

	function getCodeActions<T>(params:CodeActionParams) {
		if (!params.textDocument.uri.isFile()) {
			return [];
		}
		var actions:Array<CodeAction> = [];
		for (d in params.context.diagnostics) {
			if (!(d.code is Int)) // our codes are int, so we don't handle other stuff
				continue;
			var code = new DiagnosticKind<T>(d.code);
			actions = actions.concat(switch code {
				case UnusedImport: getUnusedImportActions(params, d);
				case UnresolvedIdentifier: getUnresolvedIdentifierActions(params, d);
				case CompilerError: getCompilerErrorActions(params, d);
				case RemovableCode: getRemovableCodeActions(params, d);
				case _: [];
			});
		}
		actions = getOrganizeImportActions(params, actions).concat(actions);
		actions = actions.filterDuplicates((a1, a2) -> Json.stringify(a1) == Json.stringify(a2));
		return actions;
	}

	function getUnusedImportActions(params:CodeActionParams, d:Diagnostic):Array<CodeAction> {
		var doc = context.documents.get(params.textDocument.uri);
		return [
			{
				title: RemoveUnusedImportUsingTitle,
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, [{range: patchRange(doc, d.range), newText: ""}]),
				diagnostics: [d]
			}
		];
	}

	function getUnresolvedIdentifierActions(params:CodeActionParams, d:Diagnostic):Array<CodeAction> {
		var actions:Array<CodeAction> = [];
		var args = getDiagnosticsArguments(params.textDocument.uri, UnresolvedIdentifier, d.range);
		for (arg in args) {
			actions = actions.concat(switch arg.kind {
				case Import: getUnresolvedImportActions(params, d, arg);
				case Typo: getTypoActions(params, d, arg);
			});
		}
		return actions;
	}

	function getUnresolvedImportActions(params:CodeActionParams, d:Diagnostic, arg):Array<CodeAction> {
		var doc = context.documents.get(params.textDocument.uri);
		var preferredStyle = context.config.user.codeGeneration.imports.style;
		var secondaryStyle:ImportStyle = if (preferredStyle == Type) Module else Type;

		var importPosition = ImportHelper.getImportPosition(doc);
		function makeImportAction(style:ImportStyle):CodeAction {
			var path = if (style == Module) TypeHelper.getModule(arg.name) else arg.name;
			return {
				title: "Import " + path,
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, [ImportHelper.createImportsEdit(doc, importPosition, [arg.name], style)]),
				diagnostics: [d]
			};
		}
		return [
			makeImportAction(preferredStyle),
			makeImportAction(secondaryStyle),
			{
				title: "Change to " + arg.name,
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, [{range: d.range, newText: arg.name}]),
				diagnostics: [d]
			}
		];
	}

	function getTypoActions(params:CodeActionParams, d:Diagnostic, arg):Array<CodeAction> {
		return [
			{
				title: "Change to " + arg.name,
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, [{range: d.range, newText: arg.name}]),
				diagnostics: [d]
			}
		];
	}

	function getCompilerErrorActions(params:CodeActionParams, d:Diagnostic):Array<CodeAction> {
		var actions:Array<CodeAction> = [];
		var arg = getDiagnosticsArguments(params.textDocument.uri, CompilerError, d.range);
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

		if (context.haxeServer.haxeVersion.major >= 4 // unsuitable error range before Haxe 4
			&& arg.contains("should be declared with 'override' since it is inherited from superclass")) {
			actions.push({
				title: "Add override keyword",
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, [{range: d.range.start.toRange(), newText: "override "}]),
				diagnostics: [d]
			});
		}

		return actions;
	}

	function getRemovableCodeActions(params:CodeActionParams, d:Diagnostic):Array<CodeAction> {
		var range = getDiagnosticsArguments(params.textDocument.uri, RemovableCode, d.range).range;
		if (range == null)
			return [];
		return [
			{
				title: "Remove",
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, [{range: range, newText: ""}]),
				diagnostics: [d]
			}
		];
	}

	function getOrganizeImportActions(params:CodeActionParams, existingActions:Array<CodeAction>):Array<CodeAction> {
		var doc = context.documents.get(params.textDocument.uri);
		var map = diagnosticsArguments[params.textDocument.uri];
		var fixes = if (map == null) [] else [
			for (key in map.keys())
				if (key.code == UnusedImport)
					{range: patchRange(doc, key.range), newText: ""}
		];

		var edit = WorkspaceEditHelper.create(context, params, fixes);
		var diagnostics = existingActions.filter(action -> action.title == RemoveUnusedImportUsingTitle)
			.map(action -> action.diagnostics)
			.flatten()
			.array();
		var actions = [
			{
				title: RemoveAllUnusedImportsUsingsTitle,
				kind: SourceOrganizeImports,
				edit: edit,
				diagnostics: diagnostics
			}
		];

		if (diagnostics.length > 0 && fixes.length > 1) {
			actions.push({
				title: RemoveAllUnusedImportsUsingsTitle,
				kind: QuickFix,
				edit: edit,
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

	inline function getDiagnosticsArguments<T>(uri:DocumentUri, kind:DiagnosticKind<T>, range:Range):T {
		var map = diagnosticsArguments[uri];
		if (map == null)
			return null;
		return map.get({code: kind, range: range});
	}
}

private enum abstract UnresolvedIdentifierSuggestion(Int) {
	var Import;
	var Typo;
}

private enum abstract DiagnosticKind<T>(Int) from Int to Int {
	var UnusedImport:DiagnosticKind<Void>;
	var UnresolvedIdentifier:DiagnosticKind<Array<{kind:UnresolvedIdentifierSuggestion, name:String}>>;
	var CompilerError:DiagnosticKind<String>;
	var RemovableCode:DiagnosticKind<{description:String, range:Range}>;
	var ParserError:DiagnosticKind<String>;
	var DeprecationWarning:DiagnosticKind<String>;
	var InactiveBlock:DiagnosticKind<Void>;

	public inline function new(i:Int) {
		this = i;
	}

	public function getMessage(args:T) {
		return switch (this : DiagnosticKind<T>) {
			case UnusedImport: "Unused import/using";
			case UnresolvedIdentifier: "Unresolved identifier";
			case CompilerError: args.trim();
			case RemovableCode: args.description;
			case ParserError: args;
			case DeprecationWarning: args;
			case InactiveBlock: "Inactive conditional compilation block";
		}
	}
}

private typedef HaxeDiagnostic<T> = {
	var kind:DiagnosticKind<T>;
	var ?range:Range;
	var severity:DiagnosticSeverity;
	var args:T;
}

private typedef HaxeDiagnosticResponse<T> = {
	var ?file:FsPath;
	var diagnostics:Array<HaxeDiagnostic<T>>;
}

private typedef DiagnosticsMapKey = {code:Int, range:Range};

private class DiagnosticsMap<T> extends haxe.ds.BalancedTree<DiagnosticsMapKey, T> {
	override function compare(k1:DiagnosticsMapKey, k2:DiagnosticsMapKey) {
		var start1 = k1.range.start;
		var start2 = k2.range.start;
		var end1 = k1.range.end;
		var end2 = k2.range.end;
		inline function compare(i1, i2, e)
			return i1 < i2 ? -1 : i1 > i2 ? 1 : e;
		return compare(k1.code, k2.code,
			compare(start1.line, start2.line,
				compare(start1.character, start2.character, compare(end1.line, end2.line, compare(end1.character, end2.character, 0)))));
	}
}

package haxeLanguageServer.features.haxe;

import haxe.Json;
import haxe.display.JsonModuleTypes;
import haxe.ds.BalancedTree;
import haxe.io.Path;
import haxeLanguageServer.LanguageServerMethods;
import haxeLanguageServer.helper.PathHelper;
import haxeLanguageServer.protocol.DisplayPrinter;
import haxeLanguageServer.server.DisplayResult;
import js.node.ChildProcess;

using Lambda;

class DiagnosticsFeature {
	public static inline final DiagnosticsSource = "diagnostics";
	public static inline final SortImportsUsingsTitle = "Sort imports/usings";
	public static inline final OrganizeImportsUsingsTitle = "Organize imports/usings";
	public static inline final RemoveUnusedImportUsingTitle = "Remove unused import/using";
	public static inline final RemoveAllUnusedImportsUsingsTitle = "Remove all unused imports/usings";

	final context:Context;
	final diagnosticsArguments:Map<DocumentUri, DiagnosticsMap<Any>>;
	final errorUri:DocumentUri;

	var haxelibPath:Null<FsPath>;

	public function new(context:Context) {
		this.context = context;
		diagnosticsArguments = new Map();
		errorUri = new FsPath(Path.join([context.workspacePath.toString(), "Error"])).toUri();

		ChildProcess.exec(context.config.haxelib.executable + " config", (error, stdout, stderr) -> haxelibPath = new FsPath(stdout.trim()));

		context.languageServerProtocol.onNotification(LanguageServerMethods.RunGlobalDiagnostics, onRunGlobalDiagnostics);
	}

	function onRunGlobalDiagnostics(_) {
		final stopProgress = context.startProgress("Collecting Diagnostics");
		final onResolve = context.startTimer("@diagnostics");

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
		final problemMatcher = ~/(.+):(\d+): (?:lines \d+-(\d+)|character(?:s (\d+)-| )(\d+)) : (?:(Warning) : )?(.*)/;
		if (!problemMatcher.match(error))
			return false;

		var file = problemMatcher.matched(1);
		if (!Path.isAbsolute(file))
			file = Path.join([Sys.getCwd(), file]);

		final targetUri = new FsPath(file).toUri();
		if (targetUri != uri)
			return false; // only allow error reply diagnostics in current file for now (clearing becomes annoying otherwise...)

		if (isPathFiltered(targetUri.toFsPath()))
			return false;

		inline function getInt(i)
			return Std.parseInt(problemMatcher.matched(i));

		final line = getInt(2);
		var endLine = getInt(3);
		final column = getInt(4);
		final endColumn = getInt(5);
		if (line == null) {
			return false;
		}

		function makePosition(line:Int, character:Null<Int>) {
			return {
				line: line - 1,
				character: if (character == null) 0 else context.displayOffsetConverter.positionCharToZeroBasedColumn(character)
			}
		}

		if (endLine == null)
			endLine = line;
		final position = makePosition(line, column);
		final endPosition = makePosition(endLine, endColumn);

		final diag = {
			range: {start: position, end: endPosition},
			source: DiagnosticsSource,
			severity: DiagnosticSeverity.Error,
			message: problemMatcher.matched(7)
		};
		publishDiagnostic(targetUri, diag, error);
		return true;
	}

	function extractDiagnosticsFromHaxeError2(error:String):Bool {
		final problemMatcher = ~/^(Error): (.*)$/;
		if (!problemMatcher.match(error)) {
			return false;
		}
		final diag = {
			range: {start: {line: 0, character: 0}, end: {line: 0, character: 0}},
			source: DiagnosticsSource,
			severity: DiagnosticSeverity.Error,
			message: problemMatcher.matched(2)
		};
		publishDiagnostic(errorUri, diag, error);
		return true;
	}

	function publishDiagnostic(uri:DocumentUri, diag:Diagnostic, error:String) {
		context.languageServerProtocol.sendNotification(PublishDiagnosticsNotification.type, {uri: uri, diagnostics: [diag]});
		final argumentsMap = diagnosticsArguments[uri] = new DiagnosticsMap();
		argumentsMap.set({code: CompilerError, range: diag.range}, error);
	}

	function processDiagnosticsReply(uri:Null<DocumentUri>, onResolve:(result:Dynamic, ?debugInfo:String) -> Void, result:DisplayResult) {
		clearDiagnostics(errorUri);
		final data:Array<HaxeDiagnosticResponse<Any>> = switch result {
			case DResult(s):
				try {
					Json.parse(s);
				} catch (e) {
					trace("Error parsing diagnostics response: " + e);
					return;
				}
			case DCancelled:
				return;
		}
		var count = 0;
		final sent = new Map<DocumentUri, Bool>();
		for (data in data) {
			count += data.diagnostics.length;

			var file = data.file;
			if (file == null) {
				// LSP always needs a URI for now (https://github.com/Microsoft/language-server-protocol/issues/256)
				file = errorUri.toFsPath();
			}
			if (isPathFiltered(file))
				continue;

			final uri = file.toUri();
			final argumentsMap = diagnosticsArguments[uri] = new DiagnosticsMap();

			final newDiagnostics = filterRelevantDiagnostics(data.diagnostics);
			final diagnostics = new Array<Diagnostic>();
			for (hxDiag in newDiagnostics) {
				final kind:Int = hxDiag.kind;
				final diag:Diagnostic = {
					range: if (hxDiag.range == null) {
						// range is not optional in the LSP yet
						{
							start: {line: 0, character: 0},
							end: {line: 0, character: 0}
						}
					} else {
						hxDiag.range;
					},
					source: DiagnosticsSource,
					code: kind,
					severity: hxDiag.severity,
					message: hxDiag.kind.getMessage(hxDiag.args)
				}
				if (kind == RemovableCode || kind == UnusedImport || diag.message.contains("has no effect") || kind == InactiveBlock) {
					diag.severity = Hint;
					diag.tags = [Unnecessary];
				}
				if (diag.message == "This case is unused") {
					diag.tags = [Unnecessary];
				}
				if (kind == DeprecationWarning) {
					diag.tags = [Deprecated];
				}
				argumentsMap.set({code: kind, range: diag.range}, hxDiag.args);
				diagnostics.push(diag);
			}
			context.languageServerProtocol.sendNotification(PublishDiagnosticsNotification.type, {uri: uri, diagnostics: diagnostics});
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

	function isPathFiltered(path:FsPath):Bool {
		final pathFilter = PathHelper.preparePathFilter(context.config.user.diagnosticsPathFilter, haxelibPath, context.workspacePath);
		return !PathHelper.matches(path, pathFilter);
	}

	function filterRelevantDiagnostics(diagnostics:Array<HaxeDiagnostic<Any>>):Array<HaxeDiagnostic<Any>> {
		// hide regular compiler errors while there's parser errors, they can be misleading
		final hasProblematicParserErrors = diagnostics.find(d -> switch (d.kind : Int) {
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
		final hasCompilerErrors = diagnostics.find(d -> d.kind == cast CompilerError) != null;
		if (hasCompilerErrors) {
			diagnostics = diagnostics.filter(d -> d.kind != cast UnusedImport);
		}

		// hide inactive blocks that are contained within other inactive blocks
		diagnostics = diagnostics.filter(a -> !diagnostics.exists(b -> a != b && a.range != null && b.range != null && b.range.contains(a.range)));

		return diagnostics;
	}

	public function clearDiagnostics(uri:DocumentUri) {
		if (diagnosticsArguments.remove(uri)) {
			context.languageServerProtocol.sendNotification(PublishDiagnosticsNotification.type, {uri: uri, diagnostics: []});
		}
	}

	public function publishDiagnostics(uri:DocumentUri) {
		if (!uri.isFile() || isPathFiltered(uri.toFsPath())) {
			clearDiagnostics(uri);
			return;
		}
		final doc:Null<HaxeDocument> = context.documents.getHaxe(uri);
		if (doc != null) {
			final onResolve = context.startTimer("@diagnostics");
			context.callDisplay("@diagnostics", [doc.uri.toFsPath() + "@0@diagnostics"], null, null, processDiagnosticsReply.bind(uri, onResolve),
				processErrorReply.bind(uri));
		}
	}

	public function getArguments<T>(uri:DocumentUri, kind:DiagnosticKind<T>, range:Range):Null<T> {
		final map = diagnosticsArguments[uri];
		@:nullSafety(Off) // ?
		return if (map == null) null else map.get({code: kind, range: range});
	}

	public function getArgumentsMap(uri:DocumentUri):Null<DiagnosticsMap<Any>> {
		return diagnosticsArguments[uri];
	}
}

enum abstract UnresolvedIdentifierSuggestion(Int) {
	final Import;
	final Typo;
}

enum abstract MissingFieldCauseKind<T>(String) {
	final AbstractParent:MissingFieldCauseKind<{parent:JsonTypePathWithParams}>;
	final ImplementedInterface:MissingFieldCauseKind<{parent:JsonTypePathWithParams}>;
	final PropertyAccessor:MissingFieldCauseKind<{property:JsonClassField, isGetter:Bool}>;
}

typedef MissingFieldCause<T> = {
	var kind:MissingFieldCauseKind<T>;
	var args:T;
}

typedef MissingField = {
	var field:JsonClassField;
	var type:JsonType<Dynamic>;

	/**
		When implementing multiple interfaces, there can be field duplicates among them. This flag is only
		true for the first such occurrence of a field, so that the "Implement all" code action doesn't end
		up implementing the same field multiple times.
	**/
	var unique:Bool;
}

typedef MissingFieldDiagnostic = {
	var fields:Array<MissingField>;
	var cause:MissingFieldCause<Dynamic>;
}

typedef MissingFieldDiagnostics = {
	var moduleType:JsonModuleType<Dynamic>;
	var moduleFile:String;
	var entries:Array<MissingFieldDiagnostic>;
}

enum abstract DiagnosticKind<T>(Int) from Int to Int {
	final UnusedImport:DiagnosticKind<Void>;
	final UnresolvedIdentifier:DiagnosticKind<Array<{kind:UnresolvedIdentifierSuggestion, name:String}>>;
	final CompilerError:DiagnosticKind<String>;
	final RemovableCode:DiagnosticKind<{description:String, range:Range}>;
	final ParserError:DiagnosticKind<String>;
	final DeprecationWarning:DiagnosticKind<String>;
	final InactiveBlock:DiagnosticKind<Void>;
	final MissingFields:DiagnosticKind<MissingFieldDiagnostics>;
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
			case MissingFields:
				var printer = new DisplayPrinter(Never);
				var cause = args.entries.map(diag -> switch (diag.cause.kind) {
					case AbstractParent: printer.printPathWithParams(diag.cause.args.parent);
					case ImplementedInterface: printer.printPathWithParams(diag.cause.args.parent);
					case PropertyAccessor: diag.cause.args.property.name;
				}).join(", ");
				"Missing fields for " + cause;
		}
	}
}

private typedef HaxeDiagnostic<T> = {
	final kind:DiagnosticKind<T>;
	final ?range:Range;
	final severity:DiagnosticSeverity;
	final args:T;
}

private typedef HaxeDiagnosticResponse<T> = {
	final ?file:FsPath;
	final diagnostics:Array<HaxeDiagnostic<T>>;
}

private typedef DiagnosticsMapKey = {code:Int, range:Range};

private class DiagnosticsMap<T> extends BalancedTree<DiagnosticsMapKey, T> {
	override function compare(k1:DiagnosticsMapKey, k2:DiagnosticsMapKey) {
		final start1 = k1.range.start;
		final start2 = k2.range.start;
		final end1 = k1.range.end;
		final end2 = k2.range.end;
		inline function compare(i1, i2, e) {
			return i1 < i2 ? -1 : i1 > i2 ? 1 : e;
		}
		return compare(k1.code, k2.code,
			compare(start1.line, start2.line,
				compare(start1.character, start2.character, compare(end1.line, end2.line, compare(end1.character, end2.character, 0)))));
	}
}

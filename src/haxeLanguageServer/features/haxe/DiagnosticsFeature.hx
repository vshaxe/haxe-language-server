package haxeLanguageServer.features.haxe;

import haxe.Json;
import haxe.display.Diagnostic;
import haxe.display.Display.DiagnosticsParams;
import haxe.display.Display.DisplayMethods;
import haxe.display.JsonModuleTypes;
import haxe.ds.BalancedTree;
import haxe.io.Path;
import haxeLanguageServer.LanguageServerMethods;
import haxeLanguageServer.ProcessUtil.shellEscapeCommand;
import haxeLanguageServer.helper.PathHelper;
import haxeLanguageServer.helper.SemVer;
import haxeLanguageServer.protocol.DisplayPrinter;
import haxeLanguageServer.server.DisplayResult;
import js.Node.clearImmediate;
import js.Node.setImmediate;
import js.node.ChildProcess;
import jsonrpc.CancellationToken;
import languageServerProtocol.Types.Diagnostic;
import languageServerProtocol.Types.Location;

using Lambda;
using haxeLanguageServer.features.haxe.DiagnosticsFeature;

class DiagnosticsFeature {
	public static inline final SortImportsUsingsTitle = "Sort imports/usings";
	public static inline final OrganizeImportsUsingsTitle = "Organize imports/usings";
	public static inline final RemoveUnusedImportUsingTitle = "Remove unused import/using";
	public static inline final RemoveAllUnusedImportsUsingsTitle = "Remove all unused imports/usings";
	public static inline final FixAllTitle = "Fix All";

	final context:Context;
	final diagnosticsArguments:Map<DocumentUri, DiagnosticsMap<Any>>;
	final pendingRequests:Map<DocumentUri, CancellationTokenSource>;
	final errorUri:DocumentUri;

	final useJsonRpc:Bool;
	final timerName:String;

	var haxelibPath:Null<FsPath>;

	public function new(context:Context) {
		this.context = context;
		diagnosticsArguments = new Map();
		pendingRequests = new Map();
		errorUri = new FsPath(Path.join([context.workspacePath.toString(), "Error"])).toUri();

		useJsonRpc = context.haxeServer.supports(DisplayMethods.Diagnostics);
		if (context.config.user.useLegacyDiagnostics) {
			useJsonRpc = false;
		}
		timerName = useJsonRpc ? DisplayMethods.Diagnostics : "@diagnostics";

		ChildProcess.exec(shellEscapeCommand(context.config.haxelib.executable) + " config", {shell: true},
			(error, stdout, stderr) -> haxelibPath = new FsPath(stdout.trim()));

		context.languageServerProtocol.onNotification(LanguageServerMethods.RunGlobalDiagnostics, onRunGlobalDiagnostics);
	}

	function onRunGlobalDiagnostics(_) {
		final stopProgress = context.startProgress("Collecting Diagnostics");
		final onResolve = context.startTimer(timerName);

		if (useJsonRpc) {
			context.callHaxeMethod(DisplayMethods.Diagnostics, {}, null, result -> {
				processDiagnosticsReply(null, onResolve, result);
				context.languageServerProtocol.sendNotification(LanguageServerMethods.DidRunRunGlobalDiagnostics);
				stopProgress();
				return null;
			}, function(error) {
				processErrorReply(null, error);
				stopProgress();
			});
		} else {
			context.callDisplay("global diagnostics", ["diagnostics"], null, null, function(result) {
				final data = parseLegacyDiagnostics(result);
				if (data == null) {
					clearDiagnosticsOnClient(errorUri);
				} else {
					processDiagnosticsReply(null, onResolve, data);
				}
				context.languageServerProtocol.sendNotification(LanguageServerMethods.DidRunRunGlobalDiagnostics);
				stopProgress();
			}, function(error) {
				processErrorReply(null, error);
				stopProgress();
			});
		}
	}

	function parseLegacyDiagnostics(result:DisplayResult):Null<ReadOnlyArray<{file:haxe.display.FsPath, diagnostics:ReadOnlyArray<haxe.display.Diagnostic<Any>>}>> {
		return switch result {
			case DResult(s):
				try {
					Json.parse(s);
				} catch (e) {
					trace("Error parsing diagnostics response: " + e);
					null;
				}
			case DCancelled: null;
		};
	}

	function processErrorReply(uri:Null<DocumentUri>, error:String) {
		if (!extractDiagnosticsFromHaxeError(uri, error) && !extractDiagnosticsFromHaxeError2(error)) {
			if (uri != null) {
				clearDiagnosticsOnClient(uri);
			}
			clearDiagnosticsOnClient(errorUri);
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
			severity: languageServerProtocol.Types.DiagnosticSeverity.Error,
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
			severity: languageServerProtocol.Types.DiagnosticSeverity.Error,
			message: problemMatcher.matched(2)
		};
		publishDiagnostic(errorUri, diag, error);
		return true;
	}

	function publishDiagnostic(uri:DocumentUri, diag:Diagnostic, error:String) {
		context.languageServerProtocol.sendNotification(PublishDiagnosticsNotification.type, {uri: uri, diagnostics: [diag]});
		final argumentsMap = diagnosticsArguments[uri] = new DiagnosticsMap();
		argumentsMap.set({code: DKCompilerError, range: diag.range}, error);
	}

	function processDiagnosticsReply(uri:Null<DocumentUri>, onResolve:(result:Dynamic, ?debugInfo:String) -> Void,
			data:ReadOnlyArray<{file:haxe.display.FsPath, diagnostics:ReadOnlyArray<haxe.display.Diagnostic<Any>>}>) {
		clearDiagnosticsOnClient(errorUri);
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
			final doc = context.documents.getHaxe(uri);

			final newDiagnostics = filterRelevantDiagnostics(data.diagnostics);
			final diagnostics = new Array<Diagnostic>();
			for (hxDiag in newDiagnostics) {
				final kind:Int = hxDiag.kind;
				final range:Range = if (hxDiag.range == null) {
					// range is not optional in the LSP yet
					{
						start: {line: 0, character: 0},
						end: {line: 0, character: 0}
					}
				} else {
					context.displayOffsetConverter.byteRangeToCharacterRange(hxDiag.range, doc);
				};
				final diag:Diagnostic = {
					range: range,
					code: hxDiag.code,
					severity: cast hxDiag.severity,
					message: hxDiag.kind.getMessage(doc, hxDiag.args, range),
					data: {kind: hxDiag.kind},
					relatedInformation: hxDiag.relatedInformation?.map(rel -> {
						location: Safety.let(rel.location, location -> {
							uri: location.file.toUri(),
							range: location.range,
						}),
						message: convertIndentation(rel.message, rel.depth)
					})
				}
				if (kind == ReplaceableCode || kind == DKUnusedImport || diag.message.contains("has no effect") || kind == InactiveBlock) {
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
				clearDiagnosticsOnClient(uri);
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

	function filterRelevantDiagnostics(diagnostics:ReadOnlyArray<HaxeDiagnostic<Any>>):ReadOnlyArray<HaxeDiagnostic<Any>> {
		// hide regular compiler errors while there's parser errors, they can be misleading
		final hasProblematicParserErrors = diagnostics.find(d -> switch (d.kind : Int) {
			case DKParserError: d.args != "Missing ;"; // don't be too strict
			case _: false;
		}) != null;
		if (hasProblematicParserErrors) {
			diagnostics = diagnostics.filter(d -> switch (d.kind : Int) {
				case DKCompilerError, DKUnresolvedIdentifier: false;
				case _: true;
			});
		}

		// hide unused import warnings while there's compiler errors (to avoid false positives)
		final hasCompilerErrors = diagnostics.find(d -> d.kind == cast DKCompilerError) != null;
		if (hasCompilerErrors) {
			diagnostics = diagnostics.filter(d -> d.kind != cast DKUnusedImport);
		}

		// hide inactive blocks that are contained within other inactive blocks
		diagnostics = diagnostics.filter(a -> a.kind != (cast InactiveBlock)
			|| !diagnostics.exists(b -> a != b && a.range != null && b.range != null && b.range.contains(a.range)));

		return diagnostics;
	}

	function convertIndentation(msg:String, depth:Int):String {
		if (msg.startsWith("... ")) {
			msg = msg.substr(4);
			depth++;
		}

		if (depth < 2)
			return msg;

		final buf = new StringBuf();
		for (_ in 1...depth)
			buf.add("⋅⋅⋅");
		buf.add(" ");
		buf.add(msg);
		return buf.toString();
	}

	public function clearDiagnostics(uri:DocumentUri) {
		cancelPendingRequest(uri);
		clearDiagnosticsOnClient(uri);
	}

	function clearDiagnosticsOnClient(uri:DocumentUri) {
		if (diagnosticsArguments.remove(uri)) {
			context.languageServerProtocol.sendNotification(PublishDiagnosticsNotification.type, {uri: uri, diagnostics: []});
		}
	}

	public function publishDiagnostics(uri:DocumentUri) {
		if (!uri.isFile() || isPathFiltered(uri.toFsPath())) {
			clearDiagnosticsOnClient(uri);
			return;
		}
		cancelPendingRequest(uri);
		var tokenSource = new CancellationTokenSource();
		// we delay the actual request because in some cases `clearDiagnostics` will be called right away,
		// and since diagnostics call is rather expensive, we don't want to make redundant invokations
		// one scenario where this happens is vscode document preview, see https://github.com/microsoft/vscode/issues/78453
		var immediate = setImmediate(invokePendingRequest, uri, tokenSource.token);
		tokenSource.token.setCallback(clearImmediate.bind(immediate)); // will be re-set by callDisplay later
		pendingRequests[uri] = tokenSource;
	}

	function invokePendingRequest(uri:DocumentUri, token:CancellationToken) {
		final doc:Null<HaxeDocument> = context.documents.getHaxe(uri);

		if (doc != null) {
			final onResolve = context.startTimer(timerName);
			if (useJsonRpc) {
				var params:DiagnosticsParams = {fileContents: []};

				if (context.config.user.diagnosticsForAllOpenFiles) {
					context.documents.iter(function(doc) {
						final path = doc.uri.toFsPath();
						if (doc.languageId == "haxe" && !isPathFiltered(path)) {
							params.fileContents.sure().push({file: path, contents: null});
						}
					});
				} else {
					params.file = doc.uri.toFsPath();
				}

				context.callHaxeMethod(DisplayMethods.Diagnostics, params, token, result -> {
					pendingRequests.remove(uri);
					processDiagnosticsReply(uri, onResolve, result);
					return null;
				}, error -> {
					pendingRequests.remove(uri);
					processErrorReply(uri, error);
				});
			} else {
				context.callDisplay("@diagnostics", [doc.uri.toFsPath() + "@0@diagnostics"], null, token, result -> {
					pendingRequests.remove(uri);
					final data = parseLegacyDiagnostics(result);
					if (data == null) {
						clearDiagnosticsOnClient(errorUri);
					} else {
						processDiagnosticsReply(null, onResolve, data);
					}
				}, error -> {
					pendingRequests.remove(uri);
					processErrorReply(uri, error);
				});
			}
		} else {
			pendingRequests.remove(uri);
		}
	}

	function cancelPendingRequest(uri:DocumentUri) {
		if (useJsonRpc && context.config.user.diagnosticsForAllOpenFiles) {
			for (tokenSource in pendingRequests) {
				tokenSource.cancel();
			}
			pendingRequests.clear();
		} else {
			var tokenSource = pendingRequests[uri];
			if (tokenSource != null) {
				pendingRequests.remove(uri);
				tokenSource.cancel();
			}
		}
	}

	public function getArguments<T>(uri:DocumentUri, kind:DiagnosticKind<T>, range:Null<Range>):Null<T> {
		final map = diagnosticsArguments[uri];
		@:nullSafety(Off) // ?
		return if (map == null) null else map.get({code: kind, range: range});
	}

	public function getArgumentsMap(uri:DocumentUri):Null<DiagnosticsMap<Any>> {
		return diagnosticsArguments[uri];
	}
}

class DiagnosticKindHelper {
	public static function make<T>(code:Int)
		return (code : DiagnosticKind<T>);

	public static function getMessage<T>(dk:DiagnosticKind<T>, doc:Null<HaxeDocument>, args:T, range:Range) {
		return switch dk {
			case DKUnusedImport: "Unused import/using";
			case DKUnresolvedIdentifier:
				var message = 'Unknown identifier';
				if (doc != null) {
					message += ' : ${doc.getText(range)}';
				}
				message;
			case DKCompilerError: args.trim();
			case ReplaceableCode: args.description;
			case DKParserError: args;
			case DeprecationWarning: args;
			case InactiveBlock: "Inactive conditional compilation block";
			case MissingFields:
				var printer = new DisplayPrinter(Never);
				var cause = args.entries.map(diag -> switch (diag.cause.kind) {
					case AbstractParent: printer.printPathWithParams(diag.cause.args.parent);
					case ImplementedInterface: printer.printPathWithParams(diag.cause.args.parent);
					case PropertyAccessor: diag.cause.args.property.name;
					case FieldAccess: "this";
					case FinalFields: "this";
				}).join(", ");
				"Missing fields for " + cause;
		}
	}
}

private typedef HaxeDiagnostic<T> = {
	final kind:DiagnosticKind<T>;
	final ?range:Range;
	final ?code:String;
	final severity:DiagnosticSeverity;
	final args:T;
	final relatedInformation:Null<Array<HaxeDiagnosticRelatedInformation>>;
}

private typedef HaxeDiagnosticRelatedInformation = {
	final location:{
		final file:FsPath;
		final range:Range;
	};
	final message:String;
	final depth:Int;
}

private typedef HaxeDiagnosticResponse<T> = {
	final ?file:FsPath;
	final diagnostics:Array<HaxeDiagnostic<T>>;
}

private typedef DiagnosticsMapKey = {code:Int, ?range:Range};

private class DiagnosticsMap<T> extends BalancedTree<DiagnosticsMapKey, T> {
	override function compare(k1:DiagnosticsMapKey, k2:DiagnosticsMapKey) {
		if (k1.code != k2.code)
			return k1.code - k2.code;
		if (k1.range == null && k2.range == null)
			return 0;
		if (k1.range == null)
			return -1;
		if (k2.range == null)
			return 1;

		final start1 = k1.range.start;
		final start2 = k2.range.start;
		final end1 = k1.range.end;
		final end2 = k2.range.end;
		inline function compare(i1, i2, e) {
			return i1 < i2 ? -1 : i1 > i2 ? 1 : e;
		}
		return compare(start1.line, start2.line,
			compare(start1.character, start2.character, compare(end1.line, end2.line, compare(end1.character, end2.character, 0))));
	}
}

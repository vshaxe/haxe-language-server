package haxeLanguageServer.server;

import haxe.Json;
import haxe.io.Path;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import sys.io.File;
import sys.io.FileOutput;
import sys.FileSystem;

import haxeLanguageServer.Configuration.ServerRecordingConfig;
import haxeLanguageServer.helper.FsHelper;
import haxeLanguageServer.server.ServerRecordingTools.getVcsState;

using StringTools;

@:access(haxeLanguageServer.Configuration)
@:access(haxeLanguageServer.Context)
@:access(haxeLanguageServer.server.DisplayRequest)
class ServerRecording {
	static inline var REPRO_VERSION:Float = 1.1;
	static inline var LOG_FILE:String = "repro.log";
	static inline var UNTRACKED_DIR:String = "untracked";
	static inline var FILE_CONTENTS_DIR:String = "files";

	var ready:Bool = false;
	var enabled(get, never):Bool;
	function get_enabled():Bool return ready && config.enabled;

	var startTime:Float = -1;
	var fsEventIndex:Int = 1;
	var recordingPath(get,null):String = "";
	var config:ServerRecordingConfig = Configuration.DefaultUserSettings.serverRecording;

	public function new() {}

	public function onInitialize(context:Context):Void restart(context);
	public function restartServer(reason:String, context:Context):Void {
		restart(context, context.initialized ? reason : null);
	}

	public function export(
		params:Null<{dest:String}>,
		token:CancellationToken,
		resolve:String->Void,
		reject:ResponseError<String>->Void
	):Void {
		if (!enabled) {
			return reject(new ResponseError(
				ResponseError.InternalError,
				"Was not recording haxe server"
			));
		}

		appendLines(makeEntry(Comment, 'Export requested ...'));
		var dest = params?.dest == null ? config.path : params.sure().dest;

		if (!FileSystem.isDirectory(dest)) {
			appendLines(makeEntry(Comment, 'Failed to export to $dest'));
			return reject(new ResponseError(
				ResponseError.InvalidParams,
				"Server recording export path should be a directory"
			));
		}

		// Could use startTime here I guess, but it does seem a bit weird to me
		var recordingKey = DateTools.format(Date.now(), "%Y%m%d-%H%M%S");
		try {
			var path = Path.join([dest, recordingKey]);
			appendLines(makeEntry(Comment, 'Exporting to $path ...'));
			FileSystem.createDirectory(path);

			// Save end vcs status
			// Note that untracked files will be copied asynchronously to target
			// directory and won't always all be ready when the notification is
			// sent.
			var vcsState = getVcsState(
				Path.join([recordingPath, "end.patch"]),
				Path.join([path, "endUntracked"]),
				config
			);

			switch vcsState {
				case Git(_, _, _, untrackedCopy):
					untrackedCopy
					.then((_) -> appendLines(makeEntry(Comment, 'Untracked files copied successfully')))
					.catchError((err) -> appendLines(makeEntry(Comment, 'Warning: error while saving untracked file: ${err.message}')));
				case _:
			}

			FsHelper.cp(recordingPath, path)
			.then((_) -> resolve('Exported server recording to $path'))
			.catchError((err) -> reject(new ResponseError(ResponseError.InternalError, Std.string(err), err)));
		} catch (e) {
			reject(new ResponseError(ResponseError.InternalError, e.message));
		}
	}

	public function onDisplayRequestQueued(request:DisplayRequest):Void {
		// Log requests being queued at the beginning too
		if (config == null || !config.enabled) return;

		appendLines(makeEntry(Local, 'serverRequestQueued', extractRequestId(request.args), request.label));
	}

	public function onDisplayRequestCancelled(request:DisplayRequest):Void {
		// Log requests being queued at the beginning too
		if (config == null || !config.enabled) return;

		appendLines(
			makeEntry(Local, 'serverRequestCancelled', extractRequestId(request.args), request.label),
			Json.stringify(request.args)
		);
	}

	public function onDisplayRequest(request:DisplayRequest):Void {
		if (!enabled) return;

		var delta = Date.now().getTime() - request.creationTime;
		var id = extractRequestId(request.args);

		if (delta > 5) appendLines(makeEntry(Comment, 'Request has been queued for $delta ms'));
		appendLines(makeEntry(Out, 'serverRequest', id, request.label), Json.stringify(request.args));
	}

	public function onServerMessage(request:DisplayRequest, message:String):Void {
		if (!enabled) return;

		var delta = Date.now().getTime() - request.creationTime;
		appendLines(makeEntry(Comment, 'Request total time: $delta ms'));

		request.processResult(message, onServerResponse.bind(request), onServerError.bind(request));
	}

	function onServerResponse(request:DisplayRequest, response:DisplayResult):Void {
		if (!enabled) return;

		// Compilation result is handled separately
		if (request.label == "compilation") return;

		var id = extractRequestId(request.args);

		appendLines(
			makeEntry(In, 'serverResponse', id, request.label),
			Json.stringify(response)
		);
	}

	function onServerError(request:DisplayRequest, error:String):Void {
		if (!enabled) return;
		var id = extractRequestId(request.args);

		appendLines(
			makeEntry(In, 'serverError', id, request.label),
			"<<EOF", error, "EOF"
		);
	}

	public function onDidChangeTextDocument(event:DidChangeTextDocumentParams) {
		if (!enabled) return;

		appendLines(
			makeEntry(Local, 'didChangeTextDocument'),
			Json.stringify(event)
		);
	}

	public function onFileEvent(event:FileEvent):Void {
		final kind = switch (event.type) {
			case Changed: "fileChanged";
			case Created: "fileCreated";
			case Deleted: "fileDeleted";
		};

		final path = event.uri.toFsPath().toString();
		final id = switch (event.type) {
			case Deleted: 0;
			case Changed | Created:
				final stat = FileSystem.stat(path);
				stat.size == 0 ? 0 : fsEventIndex++;
		}

		appendLines(makeEntry(Local, kind, id), '"${event.uri.toFsPath().toString()}"');

		if (id > 0) {
			ensureFileContentsDir();
			FsHelper.cp(path, Path.join([recordingPath, FILE_CONTENTS_DIR, '$id.contents']));
		}
	}

	public function onCompilationResult(res:String) {
		if (!enabled) return;

		res = res.trim();
		var fail = res.endsWith(String.fromCharCode(2));
		if (fail) res = res.substr(0, res.length - 1).trim();

		appendLines(
			makeEntry(In, 'compilationResult', fail ? "failed" : null),
			"<<EOF", res, "EOF"
		);
	}

	function restart(context:Context, ?reason:String = null):Void {
		ready = false;
		recordingPath = "";
		startTime = -1;
		fsEventIndex = 1;

		var config = context.config.user?.serverRecording;
		if (config == null) return;

		this.config = config;
		if (!config.enabled) return;

		FsHelper.rmdir(recordingPath)
		.then((_) -> start(context, reason))
		.catchError((_) -> {
			context.languageServerProtocol.sendNotification(
				ShowMessageNotification.type,
				{type: MessageType.Warning, message: 'Server recording disabled: could not remove previous files.'}
			);
		});
	}

	function start(context:Context, restartReason:Null<String>):Void {
		var now = Date.now();
		var workspace = context.workspacePath.toString();

		try FileSystem.createDirectory(recordingPath) catch (_) {
			return context.languageServerProtocol.sendNotification(
				ShowMessageNotification.type,
				{type: MessageType.Warning, message: 'Server recording disabled: could not create recording directory.'}
			);
		}

		try {
			writeLines(makeEntry(Comment, 'See https://github.com/kLabz/haxerepro for instructions'));
		} catch (_) {
			return context.languageServerProtocol.sendNotification(
				ShowMessageNotification.type,
				{type: MessageType.Warning, message: 'Server recording disabled: could not write server logs file.'}
			);
		}

		if (restartReason != null) appendLines(makeEntry(Comment, 'Restart reason: $restartReason'));

		appendLines(
			makeEntry(Local, 'userConfig'),
			Json.stringify(context.config.user),
			makeEntry(Local, 'serverRecordingConfig'),
			Json.stringify({watch: config.watch, exclude: config.exclude, excludeUntracked: config.excludeUntracked, version: REPRO_VERSION}),
			makeEntry(Local, 'displayServer'),
			Json.stringify(context.config.displayServer),
			makeEntry(Local, 'displayArguments'),
			Json.stringify(context.config.displayArguments),
			makeEntry(Local, 'haxe'),
			context.haxeServer.haxeVersion.toFullVersion(),
			makeEntry(Local, 'root', workspace)
		);

		// VCS - Detect git / svn and apply corresponding process
		var vcsState = getVcsState(
			Path.join([recordingPath, "status.patch"]),
			Path.join([recordingPath, UNTRACKED_DIR]),
			config
		);

		switch vcsState {
			case None:
				appendLines(makeEntry(Comment, 'Could not detect version control, initial state not guaranteed.'));

			case Git(ref, hasPatch, hasUntracked, untrackedCopy):
				appendLines(makeEntry(Local, 'checkoutGitRef'), ref);
				if (hasPatch) appendLines(makeEntry(Local, 'applyGitPatch'));

				if (hasUntracked) {
					appendLines(makeEntry(Local, 'addGitUntracked'));

					untrackedCopy
					.then((_) -> appendLines(makeEntry(Comment, 'Untracked files copied successfully')))
					.catchError((err) -> appendLines(makeEntry(Comment, 'Warning: error while saving untracked file: ${err.message}')));
				}

			case Svn(rev, hasPatch):
				appendLines(makeEntry(Local, 'checkoutSvnRevision'), rev);
				if (hasPatch) appendLines(makeEntry(Local, 'applySvnPatch'));
		}

		appendLines(
			makeEntry(Local, 'start'),
			makeEntry(Comment, 'Started ${DateTools.format(now, "%Y-%m-%d %H:%M:%S")}')
		);

		startTime = now.getTime();
		ready = true;
	}

	function writeLines(...lines:String):Void print(f -> File.write(f), ...lines);
	function appendLines(...lines:String):Void print(f -> File.append(f), ...lines);

	function makeEntry(dir:ServerRecordingEntryKind, command:String, ?id:Int, ?name:String):String {
		return withTiming('$dir $command' + (id == null ? '' : ' $id') + (name == null ? '' : ' "$name"'));
	}

	function withTiming(msg:String):String {
		if (startTime == -1) return msg;
		var ts = Math.round((Date.now().getTime() - startTime) / 10) / 10;
		return '+${ts}s $msg';
	}

	function ensureFileContentsDir():Void {
		var path = Path.join([recordingPath, FILE_CONTENTS_DIR]);
		if (!FileSystem.exists(path)) FileSystem.createDirectory(path);
	}

	@:noCompletion
	function print(open:String->FileOutput, ...lines:String):Void {
		if (lines.length == 0) return;

		var fpath = Path.join([recordingPath, LOG_FILE]);
		var f = open(fpath);
		for (l in lines) f.writeString('$l\n');
		f.close();
	}

	function get_recordingPath():String {
		if (recordingPath == "") recordingPath = Path.join([config.path, "current"]);
		return recordingPath;
	}

	function extractRequestId(args:Array<String>):Null<Int> {
		var len = args.length;
		if (len < 2 || args[len - 2] != "--display") return null;
		return try Json.parse(args[len - 1]).id catch (_) null;
	}
}

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

class ServerRecording {
	static inline var LOG_FILE:String = "repro.log";
	static inline var UNTRACKED_DIR:String = "untracked";
	static inline var FILE_CONTENTS_DIR:String = "files";

	var enabled(get, set):Bool;
	var _enabled:Bool = false;
	function get_enabled():Bool return _enabled && context != null;
	function set_enabled(v:Bool):Bool {
		_enabled = v;
		return get_enabled();
	}

	var fsEventIndex:Int = 1;
	var startTime:Float = -1;
	var context:Null<Context>;
	var config:ServerRecordingConfig = @:privateAccess Configuration.DefaultUserSettings.serverRecording;
	var recordingPath(get,null):String = "";

	public function new() {}

	public function start(context:Context):Void {
		this.context = context;
		this.config = context.config.user.serverRecording;
		if (!config.enabled) return;

		enabled = false;
		recordingPath = "";

		// TODO: error handling here
		(cast js.node.Fs).rmdir(recordingPath, {recursive: true, force: true}, (_) -> doStart());
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

		appendLines(withTiming("# Export requested ..."));
		var dest = params?.dest == null ? config.path : params.sure().dest;

		if (!FileSystem.isDirectory(dest)) {
			appendLines('# Failed to export to $dest');
			return reject(new ResponseError(
				ResponseError.InvalidParams,
				"Server recording export path should be a directory"
			));
		}

		// Could use startTime here I guess, but it does seem a bit weird to me
		var recordingKey = DateTools.format(Date.now(), "%Y%m%d-%H%M%S");
		try {
			var path = Path.join([dest, recordingKey]);
			appendLines('# Exporting to $path ...');
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
					.then((_) -> appendLines(withTiming('# Untracked files copied successfully')))
					.catchError((err) -> appendLines(withTiming('# Warning: error while saving untracked file: ${err.message}')));
				case _:
			}

			FsHelper.cp(recordingPath, path)
			.then((_) -> resolve('Exported server recording to $path'))
			.catchError((err) -> reject(new ResponseError(ResponseError.InternalError, Std.string(err), err)));
		} catch (e) {
			reject(new ResponseError(ResponseError.InternalError, e.message));
		}
	}

	public function onDisplayRequest(label:String, args:Array<String>):Void {
		if (!enabled) return;

		var id = switch (label) {
			// TODO: catch more special cases that don't use internal id
			case "cache build" | "compilation" | "@diagnostics": null;
			case _: @:privateAccess context.sure().haxeDisplayProtocol.nextRequestId - 1; // ew..
		};

		appendLines(
			makeEntry(Out, 'serverRequest', id, label),
			Json.stringify(args)
		);
	}

	public function onServerResponse(id:Int, method:String, response:{}):Void {
		if (!enabled) return;

		appendLines(
			makeEntry(In, 'serverResponse', id, method),
			Json.stringify(response)
		);
	}

	public function onServerError(id:Int, method:String, error:String):Void {
		if (!enabled) return;

		appendLines(
			makeEntry(In, 'serverError', id, method),
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
			// TODO: debounce (but make sure not to "merge" with next event on same file occuring
			// after a server request that would need current changes)
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

	function doStart():Void {
		var now = Date.now();

		try FileSystem.createDirectory(recordingPath) catch (_) {
			// TODO: report error (how? custom LSP notification?)
			enabled = false;
		}

		writeLines(
			'# TODO: short header with instructions',
			makeEntry(Local, 'userConfig'),
			Json.stringify(context.config.user),
			makeEntry(Local, 'serverRecordingConfig'),
			Json.stringify({watch: config.watch, exclude: config.exclude, excludeUntracked: config.excludeUntracked}),
			makeEntry(Local, 'displayServer'),
			Json.stringify(context.config.displayServer),
			makeEntry(Local, 'displayArguments'),
			Json.stringify(context.config.displayArguments)
		);

		// TODO: add exact Haxe version?

		appendLines(makeEntry(Local, 'root', context.sure().workspacePath.toString()));

		// VCS - Detect git / svn and apply corresponding process
		var vcsState = getVcsState(
			Path.join([recordingPath, "status.patch"]),
			Path.join([recordingPath, UNTRACKED_DIR]),
			config
		);

		switch vcsState {
			case None:
				appendLines(withTiming('# Could not detect version control, initial state not guaranteed.'));

			case Git(ref, hasPatch, hasUntracked, untrackedCopy):
				appendLines(makeEntry(Local, 'checkoutGitRef'), ref);
				if (hasPatch) appendLines(makeEntry(Local, 'applyGitPatch'));
				if (hasUntracked) appendLines(makeEntry(Local, 'addGitUntracked'));
				untrackedCopy
				.then((_) -> appendLines(withTiming('# Untracked files copied successfully')))
				.catchError((err) -> appendLines(withTiming('# Warning: error while saving untracked file: ${err.message}')));

			case Svn(rev, hasPatch):
				appendLines(makeEntry(Local, 'checkoutSvnRevision'), rev);
				if (hasPatch) appendLines(makeEntry(Local, 'applySvnPatch'));
		}

		appendLines(
			makeEntry(Local, 'start'),
			'# Started ${DateTools.format(now, "%Y-%m-%d %H:%M:%S")}'
		);

		startTime = now.getTime();
		enabled = true;
	}

	function writeLines(...lines:String):Void print(f -> File.write(f), ...lines);
	function appendLines(...lines:String):Void print(f -> File.append(f), ...lines);

	function makeEntry(dir:ComDirection, command:String, ?id:Int, ?name:String):String {
		return withTiming('$dir $command' + (id == null ? '' : ' $id') + (name == null ? '' : ' "$name"'));
	}

	function withTiming(msg:String):String {
		var ts = Math.round((Date.now().getTime() - startTime) / 10) / 10;
		return '+${ts}s $msg';
	}

	// TODO: error handling
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
}

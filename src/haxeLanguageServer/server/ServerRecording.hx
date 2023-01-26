package haxeLanguageServer.server;

import haxe.Json;
import haxe.io.Path;
import js.node.Buffer;
import js.node.ChildProcess;
import sys.io.File;
import sys.io.FileOutput;
import sys.FileSystem;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;

using StringTools;

class ServerRecording {
	static inline var ID:String = "current";
	static inline var LOG_FILE:String = "repro.log";
	static inline var UNTRACKED_DIR:String = "untracked";
	static inline var NEWFILES_DIR:String = "newfiles";

	var enabled(get, set):Bool;
	var _enabled:Bool = false;
	function get_enabled():Bool return _enabled && context != null;
	function set_enabled(v:Bool):Bool {
		_enabled = v;
		return get_enabled();
	}

	var fileCreationIndex:Int = 1;
	var startTime:Float = -1;
	var context:Null<Context>;
	var recordingRoot:Null<String>;
	var recordingPath:Null<String>;
	var recordingRelativeRoot(get, never):Null<String>;

	public function new() {}

	public function start(context:Context):Void {
		this.context = context;
		if (!context.config.user.enableServerRecording) return;

		enabled = false;
		recordingRoot = context.config.user.serverRecordingPath;
		recordingPath = Path.join([recordingRoot, ID]);

		// TODO: error handling here
		(cast js.node.Fs).rmdir(recordingPath.sure(), {recursive: true, force: true}, (_) -> doStart());
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
		var dest = params?.dest == null ? recordingRoot.sure() : params.sure().dest;

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

			// See https://nodejs.org/api/fs.html#fscpsrc-dest-options-callback
			// TODO: this is new API (16.7.0) so we should probably be using something else here
			// (especially since it's marked as experimental...)
			(cast js.node.Fs).cp(recordingPath.sure(), path, {
				errorOnExists: true,
				recursive: true,
				preserveTimestamps: true
			}, function(err) {
				if (err != null)
					return reject(new ResponseError(ResponseError.InternalError, Std.string(err), err));

				resolve('Exported server recording to $path');
			});
		} catch (e) {
			reject(new ResponseError(ResponseError.InternalError, e.message));
		}
	}

	@:noCompletion
	function doStart():Void {
		var now = Date.now();

		try FileSystem.createDirectory(recordingPath.sure()) catch (_) {
			// TODO: report error (how? custom LSP notification?)
			enabled = false;
		}

		writeLines(
			'# TODO: short header with instructions',
			makeEntry(Local, 'userConfig'),
			Json.stringify(context.config.user),
			makeEntry(Local, 'displayServer'),
			Json.stringify(context.config.displayServer),
			makeEntry(Local, 'displayArguments'),
			Json.stringify(context.config.displayArguments)
		);

		// TODO: add exact Haxe version?

		appendLines(makeEntry(Local, 'root', context.sure().workspacePath.toString()));

		// VCS - Detect git / svn and apply corresponding process
		var vcsReady = prepareGitState();
		if (!vcsReady) vcsReady = prepareSvnState();
		if (!vcsReady) appendLines(withTiming('# Could not detect version control, initial state not guaranteed.'));

		appendLines(
			makeEntry(Local, 'start'),
			'# Started ${DateTools.format(now, "%Y-%m-%d %H:%M:%S")}'
		);

		startTime = now.getTime();
		enabled = true;
	}

	// TODO: better error handling
	function prepareGitState():Bool {
		var revision = command("git", ["rev-parse", "HEAD"]);
		if (revision.code != 0) return false;

		appendLines(makeEntry(Local, 'checkoutGitRef'), revision.out);

		var patch = Path.join([recordingPath.sure(), "status.patch"]);
		command("git", ["diff", "--output", patch, "--patch"]);
		appendLines(makeEntry(Local, 'applyGitPatch'));

		// Get untracked files (other than recording folder)
		var untracked = command("git", ["status", "--porcelain"]).out
			.split("\n")
			.filter(l -> l.startsWith('?? '))
			.map(l -> l.substr(3))
			.filter(l -> l != recordingRelativeRoot.sure() && l != ".haxelib" && l != "dump");

		if (untracked.length > 0) {
			appendLines(makeEntry(Local, 'addGitUntracked'));

			FileSystem.createDirectory(Path.join([recordingPath.sure(), UNTRACKED_DIR]));
			for (f in untracked) {
				// See https://nodejs.org/api/fs.html#fscpsrc-dest-options-callback
				// TODO: this is new API (16.7.0) so we should probably be using something else here
				// (especially since it's marked as experimental...)
				// TODO: also, this is async but we're currently skipping waiting
				// We might also want to do something about long copy times here, because:
				// - starting Haxe LSP shouldn't take long
				// - if we're not blocking and copy takes too much time, we might end up
				//   with wrong data if it gets modified before we copy it
				if (f.startsWith('"')) f = f.substr(1);
				if (f.endsWith('"')) f = f.substr(0, f.length - 1);
				var fpath = Path.join([recordingPath.sure(), UNTRACKED_DIR, f]);
				(cast js.node.Fs).cp(f, fpath, {recursive: true}, function(err) {
					if (err != null) appendLines(withTiming('# Warning: error while saving untracked file $f: ${err.message}'));
					else appendLines(withTiming('# Untracked files copied successfully'));
				});
			}
		}

		return true;
	}

	// TODO: better error handling
	function prepareSvnState():Bool {
		var revision = command("svn", ["info", "--show-item", "revision"]);
		if (revision.code != 0) return false;

		appendLines(makeEntry(Local, 'checkoutSvnRevision'), revision.out);

		var status = command("svn", ["status"]);
		var untracked = [for (line in status.out.split('\n')) {
			if (line.charCodeAt(0) != '?'.code) continue;
			line.substr(1).trim();
		}];

		for (f in untracked) command("svn", ["add", f]);

		var patch = command("svn", ["diff", "--depth=infinity", "--patch-compatible"]);
		if (patch.out.trim().length > 0) {
			File.saveContent(Path.join([recordingPath.sure(), "status.patch"]), patch.out);
			appendLines(makeEntry(Local, 'applySvnPatch'));
		}

		for (f in untracked) command("svn", ["rm", "--keep-local", f]);

		return true;
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

	public function onFileCreation(event:FileEvent) {
		if (!enabled) return;

		var path = event.uri.toFsPath().toString();
		var content = File.getContent(path);
		var id = content == "" ? 0 : fileCreationIndex++;

		appendLines(
			makeEntry(Local, 'fileCreated', id),
			Json.stringify(event)
		);

		if (id > 0) {
			ensureNewfilesDir();
			var path = Path.join([recordingPath.sure(), NEWFILES_DIR, '$id.contents']);
			File.saveContent(path, content);
		}
	}

	public function onFileDeletion(event:FileEvent) {
		if (!enabled) return;

		appendLines(makeEntry(Local, 'fileDeleted'));
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
	function ensureNewfilesDir():Void {
		var path = Path.join([recordingPath.sure(), NEWFILES_DIR]);
		if (!FileSystem.exists(path)) FileSystem.createDirectory(path);
	}

	@:noCompletion
	function print(open:String->FileOutput, ...lines:String):Void {
		if (lines.length == 0) return;

		var fpath = Path.join([recordingRoot.sure(), ID, LOG_FILE]);
		var f = open(fpath);
		for (l in lines) f.writeString('$l\n');
		f.close();
	}

	function command(cmd:String, args:Array<String>) {
		var p = ChildProcess.spawnSync(cmd, args);

		return {
			code: p.status,
			out: p.status == 0
				? (p.stdout :Buffer).toString().trim()
				: (p.stderr:Buffer).toString().trim()
		};
	}

	function get_recordingRelativeRoot():Null<String> {
		if (recordingRoot == null) return null;

		var ret = Path.isAbsolute(recordingRoot.sure()) ? "" : recordingRoot.sure();
		if (ret.startsWith("./") || ret.startsWith("../")) ret = "";
		return ret.split("/")[0] + "/";
	}
}

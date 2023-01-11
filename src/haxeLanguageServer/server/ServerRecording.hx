package haxeLanguageServer.server;

import haxe.Json;
import haxe.io.Path;
import js.node.Buffer;
import js.node.ChildProcess;
import sys.io.File;
import sys.io.FileOutput;
import sys.FileSystem;

using StringTools;

class ServerRecording {
	static inline var ID:String = "current";
	static inline var LOG_FILE:String = "repro.log";

	final context:Context;
	var startTime:Float;
	var enabled:Bool;
	var recordingPath:String;

	public function new(context:Context) {
		this.context = context;
	}

	// TODO: expose function to save current recording (usually before restarting
	// language server, so maybe add an optional parameter to do both?)

	public function start():Void {
		if (!context.config.user.enableServerRecording) return;

		enabled = false;
		recordingPath = context.config.user.serverRecordingPath;

		var root = Path.join([recordingPath, ID]);
		// TODO: error handling here
		(cast js.node.Fs).rmdir(root, {recursive: true, force: true}, (_) -> doStart());
	}

	@:noCompletion
	function doStart():Void {
		startTime = Date.now().getTime();
		var root = Path.join([recordingPath, ID]);

		// TODO: params only available with node v12?
		try FileSystem.createDirectory(root) catch (_) {
			// TODO: report error
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

		appendLines(makeEntry(Local, 'root', context.workspacePath.toString()));
		prepareGitState(root);

		appendLines(makeEntry(Local, 'start'));
		enabled = true;
	}

	// TODO: error handling (especially when not in a git repository...)
	function prepareGitState(root:String):Void {
		var revision = command("git", ["rev-parse", "HEAD"]).out;
		appendLines(makeEntry(Local, 'checkoutGitRef'), revision);

		var patch = Path.join([root, "status.patch"]);
		command("git", ["diff", "--output", patch, "--patch"]);
		appendLines(makeEntry(Local, 'applyGitPatch'));

		var recordingRelRoot = Path.isAbsolute(recordingPath) ? "" : recordingPath;
		if (recordingRelRoot.startsWith("./") || recordingRelRoot.startsWith("../")) recordingRelRoot = "";
		recordingRelRoot = recordingRelRoot.split("/")[0] + "/";

		// Get untracked files (other than recording folder)
		var untracked = command("git", ["status", "--porcelain"]).out
			.split("\n")
			.filter(l -> l.startsWith('?? '))
			.map(l -> l.substr(3))
			.filter(l -> l != recordingRelRoot && l != ".haxelib" && l != "dump");

		if (untracked.length > 0) {
			appendLines(makeEntry(Local, 'addGitUntracked'));

			FileSystem.createDirectory(Path.join([root, "untracked"]));
			for (f in untracked) {
				// See https://nodejs.org/api/fs.html#fscpsrc-dest-options-callback
				// TODO: this is new API (16.7.0) so we should probably be using something else here
				// TODO: also, this is async but we're currently skipping waiting **and errors**
				// We might also want to do something about long copy times here, because:
				// - starting Haxe LSP shouldn't take long
				// - if we're not blocking and copy takes too much time, we might end up
				//   with wrong data if it gets modified before we copy it
				(cast js.node.Fs).cp(f, Path.join([root, "untracked", f]), {recursive: true}, function(err) {});
			}
		}
	}

	public function onDisplayRequest(label:String, args:Array<String>):Void {
		if (!enabled) return;

		// TODO: this is very hacky...
		var id = switch (label) {
			case "cache build" | "compilation" | "@diagnostics": null;
			case _: @:privateAccess context.haxeDisplayProtocol.nextRequestId;
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
			"<<EOF",
			error,
			"EOF"
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

		// TODO: add file content if any

		appendLines(
			makeEntry(Local, 'fileCreated'),
			Json.stringify(event)
		);
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
			"<<EOF",
			res,
			"EOF"
		);
	}

	function writeLines(...lines:String):Void print(f -> File.write(f), ...lines);
	function appendLines(...lines:String):Void print(f -> File.append(f), ...lines);

	function makeEntry(dir:ComDirection, command:String, ?id:Int, ?name:String):String {
		var delta = Date.now().getTime() - startTime;
		var ts = Math.round(delta/10) / 10;
		return '+${ts}s $dir $command' + (id == null ? '' : ' $id') + (name == null ? '' : ' "$name"');
	}

	@:noCompletion
	function print(open:String->FileOutput, ...lines:String):Void {
		if (lines.length == 0) return;

		var fpath = Path.join([recordingPath, ID, LOG_FILE]);
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
}

enum abstract ComDirection(String) to String {
	var In = "<";
	var Out = ">";
	var Local = "-";
}

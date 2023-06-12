package haxeLanguageServer.server;

import haxe.io.Path;
import haxeLanguageServer.Configuration.ServerRecordingConfig;
import haxeLanguageServer.helper.FsHelper;
import js.Node;
import js.lib.Promise;
import js.node.Buffer;
import js.node.ChildProcess;
import sys.FileSystem;
import sys.io.File;

enum VcsState {
	None;
	// Note: hasPatch will always be true for Git (for now at least)
	Git(ref:String, hasPatch:Bool, hasUntracked:Bool, untrackedCopy:Promise<Void>);
	Svn(rev:String, hasPatch:Bool);
}

function hasBinaryInPath(bin:String) {
	final envPath = Node.process.env["PATH"] ?? "";
	// .COM;.EXE;.BAT;.CMD;...
	final envExt = Node.process.env["PATHEXT"] ?? "";
	final delimiter = js.node.Path.delimiter;
	final paths = ~/["]+/g.replace(envPath, "").split(delimiter).map(chunk -> {
		return envExt.split(delimiter).map(ext -> {
			return Path.join([chunk, bin + ext]);
		});
	});
	final paths = Lambda.flatten(paths).filterDuplicates((a, b) -> a == b);
	for (path in paths) {
		if (FileSystem.exists(path))
			return true;
	}
	return false;
}

function command(cmd:String, args:Array<String>) {
	var p = ChildProcess.spawnSync(cmd, args);

	return {
		code: p.status,
		out: ((p.status == 0 ? p.stdout : p.stderr) : Buffer).toString().trim()
	};
}

function getVcsState(patchOutput:String, untrackedDestination:String, config:ServerRecordingConfig):VcsState {
	var ret = None;
	ret = getGitState(patchOutput, untrackedDestination, config);
	if (ret.match(None))
		ret = getSvnState(patchOutput, config);
	return ret;
}

function getGitState(patchOutput:String, untrackedDestination:String, config:ServerRecordingConfig):VcsState {
	if (!hasBinaryInPath("git"))
		return None;
	var revision = command("git", ["rev-parse", "HEAD"]);
	if (revision.code != 0)
		return None;

	command("git", applyGitExcludes(["diff", "--output", patchOutput, "--patch"], config));

	var hasUntracked = false;
	var p:Promise<Void> = Promise.resolve();

	if (!config.excludeUntracked) {
		// Get untracked files (other than recording folder)
		var untracked = command("git",
			applyGitExcludes(["status", "--porcelain"],
				config)).out.split("\n")
			.filter(l -> l.startsWith('?? '))
			.map(l -> l.substr(3))
			.filter(l -> l != recordingRelativeRoot(config) && l != ".haxelib" && l != "dump");

		if (untracked.length > 0) {
			hasUntracked = true;
			FileSystem.createDirectory(untrackedDestination);

			var promises = [];

			for (f in untracked) {
				if (f.startsWith('"'))
					f = f.substr(1);
				if (f.endsWith('"'))
					f = f.substr(0, f.length - 1);
				promises.push(FsHelper.cp(f, Path.join([untrackedDestination, f])));
			}

			p = Promise.all(promises).then((_) -> {});
		}
	}

	return Git(revision.out, true, hasUntracked, p);
}

function applyGitExcludes(args:Array<String>, config:ServerRecordingConfig):Array<String> {
	if (config.exclude.length == 0)
		return args;

	args.push("--");
	args.push(".");
	for (ex in config.exclude)
		args.push(':^$ex');
	return args;
}

function getSvnState(patchOutput:String, config:ServerRecordingConfig):VcsState {
	if (!hasBinaryInPath("svn"))
		return None;
	var revision = command("svn", ["info", "--show-item", "revision"]);
	if (revision.code != 0)
		return None;

	var hasExcludes = config.exclude.length > 0;
	var status = command("svn", ["status"]);
	var untracked = [];

	if (!config.excludeUntracked) {
		untracked = [
			for (line in status.out.split('\n')) {
				if (line.charCodeAt(0) != '?'.code)
					continue;
				var entry = line.substr(1).trim();

				if (hasExcludes) {
					var excluded = false;

					for (ex in config.exclude) {
						if (entry.startsWith(ex)) {
							excluded = true;
							break;
						}
					}

					if (excluded)
						continue;
				}

				entry;
			}
		];
	}

	for (f in untracked)
		command("svn", ["add", f]);
	var patch = command("svn", ["diff", "--depth=infinity", "--patch-compatible"]);
	var hasPatch = patch.out.trim().length > 0;
	if (hasPatch)
		File.saveContent(patchOutput, patch.out);
	for (f in untracked)
		command("svn", ["rm", "--keep-local", f]);

	return Svn(revision.out, hasPatch);
}

function recordingRelativeRoot(config:ServerRecordingConfig):String {
	var ret = Path.isAbsolute(config.path) ? "" : config.path;
	if (ret.startsWith("./") || ret.startsWith("../"))
		ret = "";
	return ret.split("/")[0] + "/";
}

package haxeLanguageServer.helper;

import haxe.io.Path;
import js.lib.Promise;
import js.node.Fs.Fs;
import sys.FileSystem;
import sys.io.File;

class FsHelper {
	public static function cp(source:String, destination:String):Promise<Void> {
		var promises = new Array<Promise<Void>>();
		var stats = Fs.lstatSync(source);

		if (stats.isDirectory()) {
			if (!FileSystem.exists(destination)) FileSystem.createDirectory(destination);
			var files = Fs.readdirSync(source);

			for (f in files) {
				var source = Path.join([source, f]);
				var destination = Path.join([destination, f]);
				var stats = Fs.statSync(source);
				promises.push((if (stats.isDirectory()) cp else copyFile)(source, destination));
			}
		} else if (stats.isFile()) {
			promises.push(copyFile(source, destination));
		}

		return Promise.all(promises).then((_) -> null);
	}

	public static function rmdir(path:String):Promise<Void> {
		try {
			if (!Fs.existsSync(path)) return Promise.resolve();

			var stats = Fs.lstatSync(path);
			if (!stats.isDirectory()) return rmFile(path);

			return Promise.all([
				for (f in Fs.readdirSync(path)) rmdir(Path.join([path, f]))
			]).then((_) -> Fs.rmdirSync(path));
		} catch (err) {
			return Promise.reject(err);
		}
	}

	public static function rmFile(path:String):Promise<Void> {
		Fs.unlinkSync(path);
		return Promise.resolve();
	}

	public static function copyFile(source:String, destination:String):Promise<Void> {
		var dir = Path.directory(destination);
		if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);

		File.copy(source, destination);
		return Promise.resolve();
	}
}

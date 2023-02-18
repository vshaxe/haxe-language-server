package haxeLanguageServer.helper;

import haxe.io.Path;
import js.lib.Promise;
import js.node.Fs.Fs;
import sys.FileSystem;
import sys.io.File;

class FsHelper {
	public static function cp(source:String, destination:String):Promise<Void> {
		var promises = new Array<Promise<Void>>();
		var stats = Fs.statSync(source);

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

	public static function copyFile(source:String, destination:String):Promise<Void> {
		var dir = Path.directory(destination);
		if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);

		File.copy(source, destination);
		return Promise.resolve();
	}
}

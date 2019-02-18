package haxeLanguageServer;

import languageServerProtocol.Types.Location;

class HaxePosition {
	static final positionRe = ~/^(.+):(\d+): (?:lines (\d+)-(\d+)|character(?:s (\d+)-| )(\d+))$/;
	static final properFileNameCaseCache = new Map<FsPath, FsPath>();
	static final isWindows = (Sys.systemName() == "Windows");

	public static function parse(pos:String, doc:TextDocument, cache:Map<FsPath, Array<String>>,
			offsetConverter:DisplayOffsetConverter):Null<Location> {
		if (!positionRe.match(pos))
			return null;

		var file = getProperFileNameCase(new FsPath(positionRe.matched(1)));
		var s = positionRe.matched(3);
		if (s != null) { // line span
			var startLine = Std.parseInt(s);
			var endLine = Std.parseInt(positionRe.matched(4));
			return {
				uri: if (file == doc.uri.toFsPath()) doc.uri else file.toUri(),
				range: {
					start: {line: startLine - 1, character: 0},
					end: {line: endLine, character: 0}, // don't -1 the end line, since we're pointing to the start of the next line
				}
			};
		} else { // char span
			var line = Std.parseInt(positionRe.matched(2));
			line--;

			var lineContent, uri;
			if (file == doc.uri.toFsPath()) {
				// it's a stdin file, we have its content in memory
				lineContent = doc.lineAt(line);
				uri = doc.uri;
			} else {
				// we have to read lines from a file on disk (cache if available)
				var lines;
				if (cache == null) {
					lines = sys.io.File.getContent(file.toString()).split("\n");
				} else {
					lines = cache[file];
					if (lines == null)
						lines = cache[file] = sys.io.File.getContent(file.toString()).split("\n");
				}
				lineContent = lines[line];
				uri = file.toUri();
			}

			var endByte = offsetConverter.positionCharToZeroBasedColumn(Std.parseInt(positionRe.matched(6)));
			var endChar = offsetConverter.byteOffsetToCharacterOffset(lineContent, endByte);

			s = positionRe.matched(5);
			var startChar;
			if (s != null) {
				var startByte = offsetConverter.positionCharToZeroBasedColumn(Std.parseInt(s));
				startChar = offsetConverter.byteOffsetToCharacterOffset(lineContent, startByte);
			} else {
				startChar = endChar;
			}

			return {
				uri: uri,
				range: {
					start: {line: line, character: startChar},
					end: {line: line, character: endChar},
				}
			};
		}
	}

	public static function getProperFileNameCase(normalizedPath:FsPath):FsPath {
		if (!isWindows)
			return normalizedPath;
		if (properFileNameCaseCache != null) {
			var cached = properFileNameCaseCache[normalizedPath];
			if (cached != null)
				return cached;
		}
		var result = normalizedPath;
		var parts = normalizedPath.toString().split("\\");
		if (parts.length > 1) {
			var acc = parts[0];
			for (i in 1...parts.length) {
				var part = parts[i];
				for (realFile in sys.FileSystem.readDirectory(acc + "\\")) {
					if (realFile.toLowerCase() == part) {
						part = realFile;
						break;
					}
				}
				acc = acc + "/" + part;
			}
			result = new FsPath(acc);
		}
		return properFileNameCaseCache[normalizedPath] = result;
	}
}

package haxeLanguageServer.helper;

import languageServerProtocol.Types.Location;

class HaxePosition {
	static final positionRe = ~/^(.+):(\d+): (?:lines (\d+)-(\d+)|character(?:s (\d+)-| )(\d+))$/;
	static final properFileNameCaseCache = new Map<FsPath, FsPath>();
	static final isWindows = (Sys.systemName() == "Windows");

	public static function parse(pos:String, doc:HxTextDocument, cache:Null<Map<FsPath, Array<String>>>,
			offsetConverter:DisplayOffsetConverter):Null<Location> {
		if (!positionRe.match(pos))
			return null;

		final file = getProperFileNameCase(new FsPath(positionRe.matched(1)));
		var s = positionRe.matched(3);
		if (s != null) { // line span
			final startLine = Std.parseInt(s).sure();
			final endLine = Std.parseInt(positionRe.matched(4)).sure();
			return {
				uri: if (file == doc.uri.toFsPath()) doc.uri else file.toUri(),
				range: {
					start: {line: startLine - 1, character: 0},
					end: {line: endLine, character: 0}, // don't -1 the end line, since we're pointing to the start of the next line
				}
			};
		} else { // char span
			var line = Std.parseInt(positionRe.matched(2)).sure();
			line--;

			var lineContent, uri;
			if (file == doc.uri.toFsPath()) {
				// it's a stdin file, we have its content in memory
				lineContent = doc.lineAt(line);
				uri = doc.uri;
			} else {
				// we have to read lines from a file on disk (cache if available)
				var lines:Null<Array<String>>;
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

			final endByte = offsetConverter.positionCharToZeroBasedColumn(Std.parseInt(positionRe.matched(6)).sure());
			final endChar = offsetConverter.byteOffsetToCharacterOffset(lineContent, endByte);

			s = positionRe.matched(5);
			final startChar = if (s != null) {
				final startByte = offsetConverter.positionCharToZeroBasedColumn(Std.parseInt(s).sure());
				offsetConverter.byteOffsetToCharacterOffset(lineContent, startByte);
			} else {
				endChar;
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
		if (!isWindows) {
			return normalizedPath;
		}
		if (properFileNameCaseCache != null) {
			final cached = properFileNameCaseCache[normalizedPath];
			if (cached != null) {
				return cached;
			}
		}
		var result = normalizedPath;
		final parts = normalizedPath.toString().split("\\");
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

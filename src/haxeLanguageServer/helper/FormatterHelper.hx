package haxeLanguageServer.helper;

import formatter.Formatter;
import tokentree.TokenTreeBuilder;

class FormatterHelper {
	public static function formatText(doc:HxTextDocument, context:Context, code:String, entryPoint:TokenTreeEntryPoint):String {
		var path;
		var origin;
		if (doc.uri.isFile()) {
			path = doc.uri.toFsPath().toString();
			origin = SourceFile(path);
		} else {
			path = context.workspacePath.toString();
			origin = Snippet;
		}
		final config = Formatter.loadConfig(path);
		switch Formatter.format(Code(code, origin), config, null, entryPoint) {
			case Success(formattedCode):
				return formattedCode;
			case Failure(_):
			case Disabled:
		}
		return code;
	}
}

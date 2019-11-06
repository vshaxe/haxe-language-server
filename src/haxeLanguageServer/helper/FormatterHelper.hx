package haxeLanguageServer.helper;

import formatter.Formatter;
import tokentree.TokenTreeBuilder;

class FormatterHelper {
	public static function formatText(doc:TextDocument, context:Context, code:String, entryPoint:TokenTreeEntryPoint):String {
		var config = Formatter.loadConfig(if (doc.uri.isFile()) {
			doc.uri.toFsPath().toString();
		} else {
			context.workspacePath.toString();
		});
		switch (Formatter.format(Code(code), config, null, entryPoint)) {
			case Success(formattedCode):
				return formattedCode;
			case Failure(_):
			case Disabled:
		}
		return code;
	}
}

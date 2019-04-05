package haxeLanguageServer.helper;

class SnippetHelper {
	public static function prettify(snippet:String):String {
		snippet = ~/\$\{\d:(.*?)\}/g.replace(snippet, "$1");
		return ~/\$\d/g.replace(snippet, "|");
	}
}

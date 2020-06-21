package haxeLanguageServer.helper;

class SnippetHelper {
	public static function prettify(snippet:String):String {
		snippet = ~/\$\{\d+:(.*?)\}/g.replace(snippet, "$1");
		return ~/\$\d+/g.replace(snippet, "|");
	}

	public static function offset(snippet:String, offset:Int):String {
		return ~/\$\{(\d+)(:.*?)?\}/g.map(snippet, function(regex) {
			final id = Std.parseInt(regex.matched(1)) + offset;
			var name = regex.matched(2);
			if (name == null) {
				name = "";
			}
			return '$${$id$name}';
		});
	}
}

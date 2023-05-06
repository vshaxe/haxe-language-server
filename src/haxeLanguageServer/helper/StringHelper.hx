package haxeLanguageServer.helper;

class StringHelper {
	static var stripAnsi = new EReg("[\u001b\u009b][[()#;?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]", "g");

	public static function clean(str:String):String
		return stripAnsi.replace(str, "");
}

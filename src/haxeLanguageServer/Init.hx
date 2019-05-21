package haxeLanguageServer;

class Init {
	public static function run() {
		#if debug
		haxe.macro.Compiler.define("uglifyjs_disabled");
		#end
	}
}

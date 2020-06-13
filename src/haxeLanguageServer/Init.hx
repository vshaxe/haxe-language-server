package haxeLanguageServer;

function run() {
	#if debug
	haxe.macro.Compiler.define("uglifyjs_disabled");
	#end
}

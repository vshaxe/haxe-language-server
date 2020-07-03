package haxeLanguageServer;

import haxe.macro.Compiler;

function run() {
	#if debug
	Compiler.define("uglifyjs_disabled");
	#end
	Compiler.define("uglifyjs_bin=" + (if (Sys.systemName() == "Windows") "node_modules\\.bin\\terser.cmd" else "./node_modules/.bin/terser"));
}

package haxeLanguageServer.features.hxml.data;

import haxeLanguageServer.features.hxml.data.Shared;
import haxeLanguageServer.helper.SemVer;
import haxeLanguageServer.protocol.DisplayPrinter;

abstract Define(DefineData) from DefineData {
	public function printDetails(haxeVersion:SemVer):String {
		var details = new DisplayPrinter().printMetadataDetails({
			name: getRealName(),
			doc: this.doc,
			links: cast this.links,
			platforms: cast this.platforms,
			parameters: cast this.params,
			targets: [],
			internal: false,
			origin: cast this.origin
		});
		final info = DefineVersions[this.name];
		final since = info?.since;
		final until = info?.until;
		function youAreUsing() {
			return if (isAvailable(haxeVersion)) '' else ' (you are using $haxeVersion)';
		}
		if (since != null && until != null) {
			details += '\n_Available from Haxe ${since} to ${until}${youAreUsing()}_';
		} else if (since != null) {
			details += '\n_Available since Haxe ${since}${youAreUsing()}_';
		} else if (until != null) {
			details += '\n_Available until Haxe ${until}${youAreUsing()}_';
		}
		return details;
	}

	static function normalizeName(name:String) {
		return name.replace("_", "-");
	}

	public function getRealName():String {
		return normalizeName(this.define);
	}

	public function matches(name:String):Bool {
		return normalizeName(name) == normalizeName(this.define);
	}

	public function hasParams():Bool {
		return this.params != null || getEnumValues() != null;
	}

	public function isAvailable(haxeVersion:SemVer):Bool {
		final info = DefineVersions[this.name];
		if (info == null) {
			return true;
		}
		if (info.since != null && info.since > haxeVersion) {
			return false;
		}
		if (info.until != null && haxeVersion > info.until) {
			return false;
		}
		return true;
	}

	public function getEnumValues():Null<EnumValues> {
		return DefineEnums[this.name];
	}
}

private typedef DefineData = {
	final ?devcomment:String;
	final name:String;
	final define:String;
	final doc:String;
	final ?platforms:ReadOnlyArray<String>;
	final ?params:ReadOnlyArray<String>;
	final ?links:ReadOnlyArray<String>;
	final ?reserved:Bool;
	final ?origin:String;
}

typedef VersionInfo = {
	final ?since:SemVer;
	final ?until:SemVer;
}

private final DefineVersions:Map<String, VersionInfo> = {
	final v4_0_0_rc3 = new SemVer(4, 0, 0, "rc.3");
	final v4_0_0_rc4 = new SemVer(4, 0, 0, "rc.4");
	final v4_1_0 = new SemVer(4, 1, 0);
	final v4_2_0 = new SemVer(4, 2, 0);
	[
		"CsVer" => {
			since: v4_0_0_rc3
		},
		"NetcoreVer" => {
			since: v4_0_0_rc3
		},
		"DumpPath" => {
			since: v4_0_0_rc4
		},
		"KeepInlinePositions" => {
			since: v4_0_0_rc4
		},
		"StdEncodingUtf8" => {
			since: v4_1_0
		},
		"NoTre" => {
			since: v4_1_0
		},
		"JarLegacyLoader" => {
			since: v4_2_0
		},
		"NoCOpt" => {
			until: v4_1_0
		},
		"OldConstructorInline" => {
			until: v4_1_0
		},
		"JvmCompressionLevel" => {
			since: v4_2_0
		},
		"JvmDynamicLevel" => {
			since: v4_2_0
		}
	];
}

private function integers(from:Int, to:Int):EnumValues {
	return [for (i in from...to + 1) {name: Std.string(i)}];
}

private final DefineEnums:Map<String, EnumValues> = [
	"Dce" => DceEnumValues,
	"Dump" => [{name: "pretty"}, {name: "record"}, {name: "position"}, {name: "legacy"}],
	"HlVer" => [{name: "1.10.0"}, {name: "1.11.0"}, {name: "1.12.0"}],
	"JavaVer" => [{name: "7"}, {name: "6"}, {name: "5"}],
	"JsEs" => [{name: "6"}, {name: "5"}, {name: "3"}],
	"LuaVer" => [{name: "5.2"}, {name: "5.1"}],
	"NetTarget" => [
		{name: "net"},
		{name: "netcore", description: ".NET core"},
		{name: "xbox"},
		{name: "micro", description: "Micro Framework"},
		{name: "compact", description: "Compact Framework"}
	],
	"SwfCompressLevel" => integers(1, 9),
	"JvmCompressionLevel" => integers(0, 9),
	"JvmDynamicLevel" => [
		{name: "1", description: "field read/write optimization (default)"},
		{name: "0", description: "none"},
		{name: "2", description: "compile-time method closures"},
	]
];

function getDefines(includeReserved:Bool):ReadOnlyArray<Define> {
	final allDefines = Defines.concat(RemovedDefines.copy());
	return if (includeReserved) allDefines else allDefines.filter(define -> define.reserved != true);
}

private final RemovedDefines:ReadOnlyArray<DefineData> = [
	{
		"name": "NoCOpt",
		"define": "no_copt",
		"doc": "Disable completion optimization (for debug purposes)."
	},
	{
		"name": "OldConstructorInline",
		"define": "old-constructor-inline",
		"doc": "Use old constructor inlining logic (from Haxe 3.4.2) instead of the reworked version."
	},
];

// from https://github.com/HaxeFoundation/haxe/blob/development/src-json/define.json

private final Defines:ReadOnlyArray<DefineData> = [
	{
		"name": "AbsolutePath",
		"define": "absolute_path",
		"doc": "Print absolute file path in trace output."
	},
	{
		"name": "AdvancedTelemetry",
		"define": "advanced-telemetry",
		"doc": "Allow the SWF to be measured with Monocle tool.",
		"platforms": ["flash"]
	},
	{
		"name": "AnalyzerOptimize",
		"define": "analyzer_optimize",
		"doc": "Perform advanced optimizations."
	},
	{
		"name": "AnnotateSource",
		"define": "annotate_source",
		"doc": "Add additional comments to generated source code.",
		"platforms": ["cpp"]
	},
	{
		"name": "CheckXmlProxy",
		"define": "check_xml_proxy",
		"doc": "Check the used fields of the XML proxy."
	},
	{
		"name": "CoreApi",
		"define": "core_api",
		"doc": "Defined in the core API context."
	},
	{
		"name": "CoreApiSerialize",
		"define": "core_api_serialize",
		"doc": "Mark some generated core API classes with the `Serializable` attribute on C#.",
		"platforms": ["cs"]
	},
	{
		"name": "Cppia",
		"define": "cppia",
		"doc": "Generate cpp instruction assembly."
	},
	{
		"name": "CsVer",
		"define": "cs_ver",
		"doc": "The C# version to target.",
		"platforms": ["cs"],
		"params": ["version"]
	},
	{
		"name": "NoCppiaAst",
		"define": "nocppiaast",
		"doc": "Use legacy cppia generation."
	},
	{
		"name": "Dce",
		"define": "dce",
		"doc": "Set the dead code elimination mode. (default: std)",
		"params": ["mode: std | full | no"],
		"links": ["https://haxe.org/manual/cr-dce.html"]
	},
	{
		"name": "DceDebug",
		"define": "dce_debug",
		"doc": "Show DCE log.",
		"links": ["https://haxe.org/manual/cr-dce.html"]
	},
	{
		"name": "Debug",
		"define": "debug",
		"doc": "Activated when compiling with -debug."
	},
	{
		"name": "DisableUnicodeStrings",
		"define": "disable_unicode_strings",
		"doc": "Disable Unicode support in `String` type.",
		"platforms": ["cpp"]
	},
	{
		"name": "Display",
		"define": "display",
		"doc": "Activated during completion.",
		"links": ["https://haxe.org/manual/cr-completion.html"]
	},
	{
		"name": "DisplayStdin",
		"define": "display_stdin",
		"doc": "Read the contents of a file specified in `--display` from standard input."
	},
	{
		"name": "DllExport",
		"define": "dll_export",
		"doc": "GenCPP experimental linking.",
		"platforms": ["cpp"]
	},
	{
		"name": "DllImport",
		"define": "dll_import",
		"doc": "Handle Haxe-generated .NET DLL imports.",
		"platforms": ["cs"]
	},
	{
		"name": "DocGen",
		"define": "doc_gen",
		"doc": "Do not perform any removal/change in order to correctly generate documentation."
	},
	{
		"name": "Dump",
		"define": "dump",
		"doc": "Dump typed AST in dump subdirectory using specified mode or non-prettified default.",
		"params": ["mode: pretty | record | position | legacy"]
	},
	{
		"name": "DumpPath",
		"define": "dump_path",
		"doc": "Path to generate dumps to (default: \"dump\").",
		"params": ["path"]
	},
	{
		"name": "DumpDependencies",
		"define": "dump_dependencies",
		"doc": "Dump the classes dependencies in a dump subdirectory."
	},
	{
		"name": "DumpIgnoreVarIds",
		"define": "dump_ignore_var_ids",
		"doc": "Remove variable IDs from non-pretty dumps (helps with diff)."
	},
	{
		"name": "DynamicInterfaceClosures",
		"define": "dynamic_interface_closures",
		"doc": "Use slow path for interface closures to save space.",
		"platforms": ["cpp"]
	},
	{
		"name": "EraseGenerics",
		"define": "erase_generics",
		"doc": "Erase generic classes on C#.",
		"platforms": ["cs"]
	},
	{
		"name": "EvalCallStackDepth",
		"define": "eval_call_stack_depth",
		"doc": "Set maximum call stack depth for eval. (default: 1000)",
		"platforms": ["eval"],
		"params": ["depth"]
	},
	{
		"name": "EvalDebugger",
		"define": "eval_debugger",
		"doc": "Support debugger in macro/interp mode. Allows `host:port` value to open a socket. Implies eval_stack.",
		"platforms": ["eval"]
	},
	{
		"name": "EvalStack",
		"define": "eval_stack",
		"doc": "Record stack information in macro/interp mode.",
		"platforms": ["eval"]
	},
	{
		"name": "EvalTimes",
		"define": "eval_times",
		"doc": "Record per-method execution times in macro/interp mode. Implies eval_stack.",
		"platforms": ["eval"]
	},
	{
		"name": "FilterTimes",
		"define": "filter_times",
		"doc": "Record per-filter execution times upon --times."
	},
	{
		"name": "FastCast",
		"define": "fast_cast",
		"doc": "Enables an experimental casts cleanup on C# and Java.",
		"platforms": ["cs", "java"]
	},
	{
		"name": "Fdb",
		"define": "fdb",
		"doc": "Enable full flash debug infos for FDB interactive debugging.",
		"platforms": ["flash"]
	},
	{
		"name": "FileExtension",
		"define": "file_extension",
		"doc": "Output filename extension for cpp source code.",
		"platforms": ["cpp"]
	},
	{
		"name": "FlashStrict",
		"define": "flash_strict",
		"doc": "More strict typing for flash target.",
		"platforms": ["flash"]
	},
	{
		"name": "FlashUseStage",
		"define": "flash_use_stage",
		"doc": "Keep the SWF library initial stage.",
		"platforms": ["flash"]
	},
	{
		"devcomment": "force_lib_check is only here as a debug facility - compiler checking allows errors to be found more easily",
		"name": "ForceLibCheck",
		"define": "force_lib_check",
		"doc": "Force the compiler to check `--net-lib` and `–-java-lib` added classes (internal).",
		"platforms": ["cs", "java"]
	},
	{
		"name": "ForceNativeProperty",
		"define": "force_native_property",
		"doc": "Tag all properties with `:nativeProperty` metadata for 3.1 compatibility.",
		"platforms": ["cpp"]
	},
	{
		"name": "GencommonDebug",
		"define": "gencommon_debug",
		"doc": "GenCommon internal.",
		"platforms": ["cs", "java"]
	},
	{
		"name": "Haxe3Compat",
		"define": "haxe3compat",
		"doc": "Gives warnings about transition from Haxe 3.x to Haxe 4.0."
	},
	{
		"name": "HaxeBoot",
		"define": "haxe_boot",
		"doc": "Give the name 'haxe' to the flash boot class instead of a generated name.",
		"platforms": ["flash"]
	},
	{
		"name": "HaxeVer",
		"define": "haxe_ver",
		"doc": "The current Haxe version value as decimal number. E.g. 3.407 for 3.4.7.",
		"reserved": true
	},
	{
		"name": "Haxe",
		"define": "haxe",
		"doc": "The current Haxe version value in SemVer format.",
		"reserved": true
	},
	{
		"name": "HlVer",
		"define": "hl_ver",
		"doc": "The HashLink version to target. (default: 1.10.0)",
		"platforms": ["hl"],
		"params": ["version"]
	},
	{
		"name": "HxcppApiLevel",
		"define": "hxcpp_api_level",
		"doc": "Provided to allow compatibility between hxcpp versions.",
		"platforms": ["cpp"],
		"reserved": true
	},
	{
		"name": "HxcppGcGenerational",
		"define": "HXCPP_GC_GENERATIONAL",
		"doc": "Experimental Garbage Collector.",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppDebugger",
		"define": "HXCPP_DEBUGGER",
		"doc": "Include additional information for hxcpp_debugger.",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppSmartStings",
		"define": "hxcpp_smart_strings",
		"doc": "Use wide strings in hxcpp. (Turned on by default unless `-D disable_unicode_strings` is specified.)",
		"platforms": ["cpp"]
	},
	{
		"name": "IncludePrefix",
		"define": "include_prefix",
		"doc": "Prepend path to generated include files.",
		"platforms": ["cpp"]
	},
	{
		"name": "Interp",
		"define": "interp",
		"doc": "The code is compiled to be run with `--interp`."
	},
	{
		"name": "JarLegacyLoader",
		"define": "jar-legacy-loader",
		"doc": "Use the legacy loader to load .jar files on the JVM target.",
		"platforms": ["java"]
	},
	{
		"name": "JavaVer",
		"define": "java_ver",
		"doc": "Sets the Java version to be targeted.",
		"platforms": ["java"],
		"params": ["version: 5-7"]
	},
	{
		"name": "JsClassic",
		"define": "js_classic",
		"doc": "Don't use a function wrapper and strict mode in JS output.",
		"platforms": ["js"]
	},
	{
		"name": "JsEs",
		"define": "js_es",
		"doc": "Generate JS compliant with given ES standard version. (default: 5)",
		"platforms": ["js"],
		"params": ["version: 3 | 5 | 6"],
		"links": ["https://haxe.org/manual/target-javascript-es6.html"]
	},
	{
		"name": "JsEnumsAsArrays",
		"define": "js_enums_as_arrays",
		"doc": "Generate enum representation as array instead of as object.",
		"platforms": ["js"]
	},
	{
		"name": "JsUnflatten",
		"define": "js_unflatten",
		"doc": "Generate nested objects for packages and types.",
		"platforms": ["js"]
	},
	{
		"name": "JsSourceMap",
		"define": "js_source_map",
		"doc": "Generate JavaScript source map even in non-debug mode. Deprecated in favor of `-D source_map`.",
		"platforms": ["js"]
	},
	{
		"name": "SourceMap",
		"define": "source_map",
		"doc": "Generate source map for compiled files.",
		"platforms": ["php", "js"]
	},
	{
		"name": "Jvm",
		"define": "jvm",
		"doc": "Generate jvm directly.",
		"platforms": ["java"]
	},
	{
		"name": "JvmCompressionLevel",
		"define": "jvm.compression-level",
		"doc": "Set the compression level of the generated file between 0 (no compression) and 9 (highest compression). Default: 6",
		"platforms": ["java"]
	},
	{
		"name": "JvmDynamicLevel",
		"define": "jvm.dynamic-level",
		"doc": "Controls the amount of dynamic support code being generated. 0 = none, 1 = field read/write optimization (default), 2 = compile-time method closures",
		"platforms": ["java"]
	},
	{
		"name": "KeepOldOutput",
		"define": "keep_old_output",
		"doc": "Keep old source files in the output directory.",
		"platforms": ["cs", "java"]
	},
	{
		"name": "LoopUnrollMaxCost",
		"define": "loop_unroll_max_cost",
		"doc": "Maximum cost (number of expressions * iterations) before loop unrolling is canceled. (default: 250)",
		"params": ["cost"]
	},
	{
		"name": "LuaJit",
		"define": "lua_jit",
		"doc": "Enable the jit compiler for lua (version 5.2 only).",
		"platforms": ["lua"]
	},
	{
		"name": "LuaVanilla",
		"define": "lua_vanilla",
		"doc": "Generate code lacking compiled extern lib support (e.g. utf8).",
		"platforms": ["lua"]
	},
	{
		"name": "LuaVer",
		"define": "lua_ver",
		"doc": "The lua version to target.",
		"platforms": ["lua"],
		"params": ["version"]
	},
	{
		"name": "Macro",
		"define": "macro",
		"doc": "Defined when code is compiled in the macro context.",
		"links": ["https://haxe.org/manual/macro.html"],
		"reserved": true
	},
	{
		"name": "MacroTimes",
		"define": "macro_times",
		"doc": "Display per-macro timing when used with `--times`."
	},
	{
		"name": "NetVer",
		"define": "net_ver",
		"doc": "Sets the .NET version to be targeted.",
		"platforms": ["cs"],
		"params": ["version: 20-45"]
	},
	{
		"name": "NetcoreVer",
		"define": "netcore_ver",
		"doc": "Sets the .NET core version to be targeted",
		"platforms": ["cs"],
		"params": ["version: x.x.x"]
	},
	{
		"name": "NetTarget",
		"define": "net_target",
		"doc": "Sets the .NET target. `netcore` (.NET core), `xbox`, `micro` (Micro Framework), `compact` (Compact Framework) are some valid values. (default: `net`)",
		"platforms": ["cs"],
		"params": ["name"]
	},
	{
		"name": "NekoSource",
		"define": "neko_source",
		"doc": "Output neko source instead of bytecode.",
		"platforms": ["neko"]
	},
	{
		"name": "NekoV1",
		"define": "neko_v1",
		"doc": "Keep Neko 1.x compatibility.",
		"platforms": ["neko"]
	},
	{
		"name": "NetworkSandbox",
		"define": "network-sandbox",
		"doc": "Use local network sandbox instead of local file access one.",
		"platforms": ["flash"]
	},
	{
		"name": "NoCompilation",
		"define": "no-compilation",
		"doc": "Disable final compilation.",
		"platforms": ["cs", "java", "cpp", "hl"]
	},
	{
		"name": "NoDebug",
		"define": "no_debug",
		"doc": "Remove all debug macros from cpp output."
	},
	{
		"name": "NoDeprecationWarnings",
		"define": "no-deprecation-warnings",
		"doc": "Do not warn if fields annotated with `@:deprecated` are used."
	},
	{
		"name": "NoFlashOverride",
		"define": "no-flash-override",
		"doc": "Change overrides on some basic classes into HX suffixed methods",
		"platforms": ["flash"]
	},
	{
		"name": "NoOpt",
		"define": "no_opt",
		"doc": "Disable optimizations."
	},
	{
		"name": "NoInline",
		"define": "no_inline",
		"doc": "Disable inlining.",
		"links": ["https://haxe.org/manual/class-field-inline.html"]
	},
	{
		"name": "KeepInlinePositions",
		"define": "keep_inline_positions",
		"doc": "Don't substitute positions of inlined expressions with the position of the place of inlining.",
		"links": ["https://haxe.org/manual/class-field-inline.html"]
	},
	{
		"name": "NoRoot",
		"define": "no_root",
		"doc": "Generate top-level types into the `haxe.root` namespace.",
		"platforms": ["cs"]
	},
	{
		"name": "NoMacroCache",
		"define": "no_macro_cache",
		"doc": "Disable macro context caching."
	},
	{
		"name": "NoSwfCompress",
		"define": "no_swf_compress",
		"doc": "Disable SWF output compression.",
		"platforms": ["flash"]
	},
	{
		"name": "NoTraces",
		"define": "no_traces",
		"doc": "Disable all trace calls."
	},
	{
		"name": "Objc",
		"define": "objc",
		"doc": "Sets the hxcpp output to Objective-C++ classes. Must be defined for interop.",
		"platforms": ["cpp"]
	},
	{
		"name": "OldErrorFormat",
		"define": "old-error-format",
		"doc": "Use Haxe 3.x zero-based column error messages instead of new one-based format."
	},
	{
		"name": "PhpPrefix",
		"define": "php_prefix",
		"doc": "Root namespace for generated php classes. E.g. if compiled with`-D php-prefix=some.sub`, then all classes will be generated in `\\some\\sub` namespace.",
		"platforms": ["php"],
		"params": ["dot-separated namespace"]
	},
	{
		"name": "PhpLib",
		"define": "php_lib",
		"doc": "Select the name for the php lib folder.",
		"platforms": ["php"],
		"params": ["folder name"]
	},
	{
		"name": "PhpFront",
		"define": "php_front",
		"doc": "Select the name for the php front file. (default: `index.php`)",
		"platforms": ["php"],
		"params": ["filename"]
	},
	{
		"name": "PythonVersion",
		"define": "python_version",
		"doc": "The python version to target. (default: 3.3)",
		"platforms": ["python"],
		"params": ["version"]
	},
	{
		"name": "RealPosition",
		"define": "real_position",
		"doc": "Disables Haxe source mapping when targetting C#, removes position comments in Java and Php output.",
		"platforms": ["cs", "java", "php"]
	},
	{
		"name": "ReplaceFiles",
		"define": "replace_files",
		"doc": "GenCommon internal.",
		"platforms": ["cs", "java"]
	},
	{
		"name": "Scriptable",
		"define": "scriptable",
		"doc": "GenCPP internal.",
		"platforms": ["cpp"]
	},
	{
		"name": "ShallowExpose",
		"define": "shallow-expose",
		"doc": "Expose types to surrounding scope of Haxe generated closure without writing to window object.",
		"platforms": ["js"]
	},
	{
		"name": "SourceHeader",
		"define": "source-header",
		"doc": "Print value as comment on top of generated files, use '' value to disable."
	},
	{
		"name": "SourceMapContent",
		"define": "source-map-content",
		"doc": "Include the Haxe sources as part of the JS source map.",
		"platforms": ["js"]
	},
	{
		"name": "Static",
		"define": "static",
		"doc": "Defined if the current target is static.",
		"reserved": true
	},
	{
		"name": "StdEncodingUtf8",
		"define": "std-encoding-utf8",
		"doc": "Force utf8 encoding for stdin, stdout and stderr",
		"platforms": ["java", "cs", "python"]
	},
	{
		"name": "Swc",
		"define": "swc",
		"doc": "Output a SWC instead of a SWF.",
		"platforms": ["flash"],
		"reserved": true
	},
	{
		"name": "SwfCompressLevel",
		"define": "swf_compress_level",
		"doc": "Set the amount of compression for the SWF output.",
		"platforms": ["flash"],
		"params": ["level: 1-9"]
	},
	{
		"name": "SwfDebugPassword",
		"define": "swf_debug_password",
		"doc": "Set a password for debugging.",
		"platforms": ["flash"],
		"params": ["password"]
	},
	{
		"name": "SwfDirectBlit",
		"define": "swf_direct_blit",
		"doc": "Use hardware acceleration to blit graphics.",
		"platforms": ["flash"]
	},
	{
		"name": "SwfGpu",
		"define": "swf_gpu",
		"doc": "Use GPU compositing features when drawing graphics.",
		"platforms": ["flash"]
	},
	{
		"name": "SwfMetadata",
		"define": "swf_metadata",
		"doc": "Include contents of the given file as metadata in the SWF.",
		"platforms": ["flash"],
		"params": ["file"]
	},
	{
		"name": "SwfPreloaderFrame",
		"define": "swf_preloader_frame",
		"doc": "Insert empty first frame in SWF.",
		"platforms": ["flash"]
	},
	{
		"name": "SwfProtected",
		"define": "swf_protected",
		"doc": "Compile Haxe `private` as `protected` in the SWF instead of `public`.",
		"platforms": ["flash"]
	},
	{
		"name": "SwfScriptTimeout",
		"define": "swf_script_timeout",
		"doc": "Maximum ActionScript processing time before script stuck dialog box displays.",
		"platforms": ["flash"],
		"params": ["time in seconds"]
	},
	{
		"name": "SwfUseDoAbc",
		"define": "swf_use_doabc",
		"doc": "Use `DoAbc` SWF-tag instead of `DoAbcDefine`.",
		"platforms": ["flash"]
	},
	{
		"name": "Sys",
		"define": "sys",
		"doc": "Defined for all system platforms.",
		"reserved": true
	},
	{
		"name": "Unsafe",
		"define": "unsafe",
		"doc": "Allow unsafe code when targeting C#.",
		"platforms": ["cs"]
	},
	{
		"name": "UseNekoc",
		"define": "use_nekoc",
		"doc": "Use `nekoc` compiler instead of the internal one.",
		"platforms": ["neko"]
	},
	{
		"name": "Utf16",
		"define": "utf16",
		"doc": "Defined for all platforms that use UTF-16 string encoding with UCS-2 API.",
		"reserved": true
	},
	{
		"name": "Vcproj",
		"define": "vcproj",
		"doc": "GenCPP internal.",
		"platforms": ["cpp"]
	},
	{
		"name": "WarnVarShadowing",
		"define": "warn_var_shadowing",
		"doc": "Warn about shadowing variable declarations."
	},
	{
		"name": "NoTre",
		"define": "no_tre",
		"doc": "Disable tail recursion elimination."
	}
];

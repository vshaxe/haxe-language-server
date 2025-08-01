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
	final ?defaultValue:String;
	final ?signatureNeutral:Bool;
	final ?deprecated:String;
	final ?deprecatedDefine:String;
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
	final v4_last = new SemVer(4, 3, 7);
	final v5_0_0_preview1 = new SemVer(5, 0, 0, "preview.1");
	[
		"CsVer" => {
			since: v4_0_0_rc3,
			until: v4_last
		},
		"NetcoreVer" => {
			since: v4_0_0_rc3,
			until: v4_last
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
			since: v4_2_0,
			until: v4_last
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
		},
		"CoreApiSerialize" => {
			until: v4_last
		},
		"DllImport" => {
			until: v4_last
		},
		"EraseGenerics" => {
			until: v4_last
		},
		"FastCast" => {
			until: v4_last
		},
		"ForceLibCheck" => {
			until: v4_last
		},
		"GencommonDebug" => {
			until: v4_last
		},
		"JavaVer" => {
			until: v4_last
		},
		"Jvm" => {
			until: v4_last
		},
		"KeepOldOutput" => {
			until: v4_last
		},
		"NetVer" => {
			until: v4_last
		},
		"NetTarget" => {
			until: v4_last
		},
		"NoRoot" => {
			until: v4_last
		},
		"ReplaceFiles" => {
			until: v4_last
		},
		"Unsafe" => {
			until: v4_last
		},
		"AnalyzerTimes" => {
			since: v5_0_0_preview1
		},
		"DisableHxbCache" => {
			since: v5_0_0_preview1
		},
		"DisableHxbOptimizations" => {
			since: v5_0_0_preview1
		},
		"EnableParallelism" => {
			since: v5_0_0_preview1
		},
		"DumpStage" => {
			since: v5_0_0_preview1
		},
		"EvalPrintDepth" => {
			since: v5_0_0_preview1
		},
		"EvalPrettyPrint" => {
			since: v5_0_0_preview1
		},
		"FailFast" => {
			since: v5_0_0_preview1
		},
		"Haxe3" => {
			since: v5_0_0_preview1
		},
		"Haxe4" => {
			since: v5_0_0_preview1
		},
		"Haxe5" => {
			since: v5_0_0_preview1
		},
		"HaxeNext" => {
			since: v5_0_0_preview1
		},
		"HaxeOutputFile" => {
			since: v5_0_0_preview1
		},
		"HaxeOutputPart" => {
			since: v5_0_0_preview1
		},
		"Hlc" => {
			since: v5_0_0_preview1
		},
		"HxbTimes" => {
			since: v5_0_0_preview1
		},
		"HxbStats" => {
			since: v5_0_0_preview1
		},
		"HxcppGcMoving" => {
			since: v5_0_0_preview1
		},
		"HxcppGcSummary" => {
			since: v5_0_0_preview1
		},
		"HxcppGcDynamicSize" => {
			since: v5_0_0_preview1
		},
		"HxcppGcBigBlocks" => {
			since: v5_0_0_preview1
		},
		"HxcppGcDebugLevel" => {
			since: v5_0_0_preview1
		},
		"HxcppDebugLink" => {
			since: v5_0_0_preview1
		},
		"HxcppStackTrace" => {
			since: v5_0_0_preview1
		},
		"HxcppStackLine" => {
			since: v5_0_0_preview1
		},
		"HxcppCheckPointer" => {
			since: v5_0_0_preview1
		},
		"HxcppProfiler" => {
			since: v5_0_0_preview1
		},
		"HxcppTelemetry" => {
			since: v5_0_0_preview1
		},
		"HxcppCpp11" => {
			since: v5_0_0_preview1
		},
		"HxcppVerbose" => {
			since: v5_0_0_preview1
		},
		"HxcppTimes" => {
			since: v5_0_0_preview1
		},
		"HxcppM32" => {
			since: v5_0_0_preview1
		},
		"HxcppM64" => {
			since: v5_0_0_preview1
		},
		"HxcppArm64" => {
			since: v5_0_0_preview1
		},
		"HxcppLinuxArm64" => {
			since: v5_0_0_preview1
		},
		"JsGlobal" => {
			since: v5_0_0_preview1
		},
		"NekoNoHaxelibPaths" => {
			since: v5_0_0_preview1
		},
		"RetainUntypedMeta" => {
			since: v5_0_0_preview1
		},
		"SwfHeader" => {
			since: v5_0_0_preview1
		},
		"MessageReporting" => {
			since: v5_0_0_preview1
		},
		"MessageColor" => {
			since: v5_0_0_preview1
		},
		"MessageAbsolutePositions" => {
			since: v5_0_0_preview1
		},
		"MessageLogFile" => {
			since: v5_0_0_preview1
		},
		"MessageLogFormat" => {
			since: v5_0_0_preview1
		},
	];
}

private function integers(from:Int, to:Int):EnumValues {
	return [for (i in from...to + 1) {name: Std.string(i)}];
}

private final DefineEnums:Map<String, EnumValues> = [
	"Dce" => DceEnumValues,
	"Dump" => [{name: "pretty"}, {name: "record"}, {name: "position"}, {name: "legacy"}],
	"HlVer" => [for (i in 10...16) {name: "1." + Std.string(i) + ".0"}],
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
	],
	"AnalyzerTimes" => integers(0, 2),
	"DumpStage" => [
		{name: "typing"},
		{name: "casting"},
		{name: "inlining"},
		{name: "analyzing"},
		{name: "dce"}
	],
	"MessageReporting" => [{name: "classic"}, {name: "pretty"}, {name: "indent"}],
	"MessageLogFormat" => [{name: "classic"}, {name: "pretty"}, {name: "indent"}],
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
	{
		"name": "CoreApiSerialize",
		"define": "core_api_serialize",
		"doc": "Mark some generated core API classes with the `Serializable` attribute on C#.",
		"platforms": ["cs"]
	},
	{
		"name": "CsVer",
		"define": "cs_ver",
		"doc": "The C# version to target.",
		"platforms": ["cs"],
		"params": ["version"]
	},
	{
		"name": "DllImport",
		"define": "dll_import",
		"doc": "Handle Haxe-generated .NET DLL imports.",
		"platforms": ["cs"]
	},
	{
		"name": "EraseGenerics",
		"define": "erase_generics",
		"doc": "Erase generic classes on C#.",
		"platforms": ["cs"]
	},
	{
		"name": "FastCast",
		"define": "fast_cast",
		"doc": "Enables an experimental casts cleanup on C# and Java.",
		"platforms": ["cs", "java"]
	},
	{
		"devcomment": "force_lib_check is only here as a debug facility - compiler checking allows errors to be found more easily",
		"name": "ForceLibCheck",
		"define": "force_lib_check",
		"doc": "Force the compiler to check `--net-lib` and `–-java-lib` added classes (internal).",
		"platforms": ["cs", "java"]
	},
	{
		"name": "GencommonDebug",
		"define": "gencommon_debug",
		"doc": "GenCommon internal.",
		"platforms": ["cs", "java"]
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
		"name": "Jvm",
		"define": "jvm",
		"doc": "Generate jvm directly.",
		"platforms": ["java"]
	},
	{
		"name": "KeepOldOutput",
		"define": "keep_old_output",
		"doc": "Keep old source files in the output directory.",
		"platforms": ["cs", "java"]
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
		"name": "NoRoot",
		"define": "no_root",
		"doc": "Generate top-level types into the `haxe.root` namespace.",
		"platforms": ["cs"]
	},
	{
		"name": "ReplaceFiles",
		"define": "replace_files",
		"doc": "GenCommon internal.",
		"platforms": ["cs", "java"]
	},
	{
		"name": "Unsafe",
		"define": "unsafe",
		"doc": "Allow unsafe code when targeting C#.",
		"platforms": ["cs"]
	},
];

// from https://github.com/HaxeFoundation/haxe/blob/development/src-json/define.json

private final Defines:ReadOnlyArray<DefineData> = [
	{
		"name": "AbsolutePath",
		"define": "absolute-path",
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
		"define": "analyzer-optimize",
		"doc": "Perform advanced optimizations."
	},
	{
		"name": "AnalyzerTimes",
		"define": "times.analyzer",
		"deprecatedDefine": "analyzer-times",
		"signatureNeutral": true,
		"doc": "Record detailed timers for the analyzer",
		"params": ["level: 0 | 1 | 2"]
	},
	{
		"name": "AnnotateSource",
		"define": "annotate-source",
		"doc": "Add additional comments to generated source code.",
		"platforms": ["cpp"]
	},
	{
		"name": "CheckXmlProxy",
		"define": "check-xml-proxy",
		"doc": "Check the used fields of the XML proxy."
	},
	{
		"name": "CoreApi",
		"define": "core-api",
		"doc": "Defined in the core API context."
	},
	{
		"name": "Cppia",
		"define": "cppia",
		"doc": "Generate cpp instruction assembly."
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
		"defaultValue": "std",
		"links": ["https://haxe.org/manual/cr-dce.html"]
	},
	{
		"name": "DceDebug",
		"define": "dce-debug",
		"signatureNeutral": true,
		"doc": "Show DCE log.",
		"links": ["https://haxe.org/manual/cr-dce.html"]
	},
	{
		"name": "Debug",
		"define": "debug",
		"doc": "Activated when compiling with -debug."
	},
	{
		"name": "DisableHxbCache",
		"define": "disable-hxb-cache",
		"signatureNeutral": true,
		"doc": "Use in-memory cache instead of hxb powered cache."
	},
	{
		"name": "DisableHxbOptimizations",
		"define": "disable-hxb-optimizations",
		"signatureNeutral": true,
		"doc": "Disable shortcuts used by hxb cache to speed up display requests."
	},
	{
		"name": "EnableParallelism",
		"define": "enable-parallelism",
		"signatureNeutral": true,
		"doc": "Enable experimental uses of parallelism in the compiler."
	},
	{
		"name": "DisableUnicodeStrings",
		"define": "disable-unicode-strings",
		"doc": "Disable Unicode support in `String` type.",
		"platforms": ["cpp"]
	},
	{
		"name": "Display",
		"define": "display",
		"signatureNeutral": true,
		"doc": "Activated during completion.",
		"links": ["https://haxe.org/manual/cr-completion.html"]
	},
	{
		"name": "DisplayStdin",
		"define": "display-stdin",
		"signatureNeutral": true,
		"doc": "Read the contents of a file specified in `--display` from standard input."
	},
	{
		"name": "DllExport",
		"define": "dll-export",
		"doc": "GenCPP experimental linking.",
		"platforms": ["cpp"]
	},
	{
		"name": "DocGen",
		"define": "doc-gen",
		"doc": "Do not perform any removal/change in order to correctly generate documentation."
	},
	{
		"name": "Dump",
		"define": "dump",
		"signatureNeutral": true,
		"doc": "Dump typed AST in dump subdirectory using specified mode or non-prettified default.",
		"params": ["mode: pretty | record | position | legacy"]
	},
	{
		"name": "DumpStage",
		"define": "dump.stage",
		"signatureNeutral": true,
		"doc": "The compiler stage after which to generate the dump",
		"params": ["stage: typing | casting | inlining | analyzing | dce"],
		"defaultValue": "dce"
	},
	{
		"name": "DumpPath",
		"define": "dump-path",
		"signatureNeutral": true,
		"doc": "Path to generate dumps to (default: \"dump\").",
		"defaultValue": "dump",
		"params": ["path"]
	},
	{
		"name": "DumpDependencies",
		"define": "dump-dependencies",
		"signatureNeutral": true,
		"doc": "Dump the classes dependencies in a dump subdirectory."
	},
	{
		"name": "DumpIgnoreVarIds",
		"define": "dump-ignore-var-ids",
		"signatureNeutral": true,
		"doc": "Remove variable IDs from non-pretty dumps (helps with diff).",
		"defaultValue": "1"
	},
	{
		"name": "DynamicInterfaceClosures",
		"define": "dynamic-interface-closures",
		"doc": "Use slow path for interface closures to save space.",
		"platforms": ["cpp"]
	},
	{
		"name": "EvalCallStackDepth",
		"define": "eval-call-stack-depth",
		"doc": "Set maximum call stack depth for eval. (default: 1000)",
		"platforms": ["eval"],
		"defaultValue": "1000",
		"params": ["depth"]
	},
	{
		"name": "EvalDebugger",
		"define": "eval-debugger",
		"doc": "Support debugger in macro/interp mode. Allows `host:port` value to open a socket. Implies eval-stack.",
		"platforms": ["eval"]
	},
	{
		"name": "EvalPrintDepth",
		"define": "eval-print-depth",
		"doc": "Set maximum print depth (before replacing with '<...>') for eval. (default: 5)",
		"platforms": ["eval"],
		"defaultValue": "5",
		"params": ["depth"]
	},
	{
		"name": "EvalPrettyPrint",
		"define": "eval-pretty-print",
		"doc": "Enable indented output for eval printing.",
		"platforms": ["eval"]
	},
	{
		"name": "EvalStack",
		"define": "eval-stack",
		"doc": "Record stack information in macro/interp mode.",
		"platforms": ["eval"]
	},
	{
		"name": "EvalTimes",
		"define": "times.eval",
		"deprecatedDefine": "eval-times",
		"signatureNeutral": true,
		"doc": "Record per-method execution times in macro/interp mode. Implies eval-stack.",
		"platforms": ["eval"]
	},
	{
		"name": "FailFast",
		"define": "fail-fast",
		"signatureNeutral": true,
		"doc": "Abort compilation when first error occurs."
	},
	{
		"name": "FilterTimes",
		"define": "times.filter",
		"deprecatedDefine": "filter-times",
		"signatureNeutral": true,
		"doc": "Record per-filter execution times upon --times."
	},
	{
		"name": "Fdb",
		"define": "fdb",
		"doc": "Enable full flash debug infos for FDB interactive debugging.",
		"platforms": ["flash"]
	},
	{
		"name": "FileExtension",
		"define": "file-extension",
		"doc": "Output filename extension for cpp source code.",
		"platforms": ["cpp"]
	},
	{
		"name": "FlashStrict",
		"define": "flash-strict",
		"doc": "More strict typing for flash target.",
		"platforms": ["flash"]
	},
	{
		"name": "FlashUseStage",
		"define": "flash-use-stage",
		"doc": "Keep the SWF library initial stage.",
		"platforms": ["flash"]
	},
	{
		"name": "ForceNativeProperty",
		"define": "force-native-property",
		"doc": "Tag all properties with `:nativeProperty` metadata for 3.1 compatibility.",
		"platforms": ["cpp"]
	},
	{
		"name": "Haxe3Compat",
		"define": "haxe3compat",
		"doc": "Gives warnings about transition from Haxe 3.x to Haxe 4.0.",
		"deprecated": "This flag is no longer supported in Haxe 5"
	},
	{
		"name": "HaxeBoot",
		"define": "haxe-boot",
		"doc": "Give the name 'haxe' to the flash boot class instead of a generated name.",
		"platforms": ["flash"]
	},
	{
		"name": "HaxeVer",
		"define": "haxe-ver",
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
		"name": "Haxe3",
		"define": "haxe3",
		"doc": "The current Haxe major version is >= 3.",
		"defaultValue": "1",
		"reserved": true
	},
	{
		"name": "Haxe4",
		"define": "haxe4",
		"doc": "The current Haxe major version is >= 4.",
		"defaultValue": "1",
		"reserved": true
	},
	{
		"name": "Haxe5",
		"define": "haxe5",
		"doc": "The current Haxe major version is >= 5.",
		"defaultValue": "1",
		"reserved": true
	},
	{
		"name": "HaxeNext",
		"define": "haxe-next",
		"doc": "Enable experimental features that are meant to be released on next Haxe version."
	},
	{
		"name": "HaxeOutputFile",
		"define": "HAXE-OUTPUT-FILE",
		"doc": "Force the full output name of the executable/library without library prefix and debug suffix.",
		"platforms": ["cpp"],
		"params": ["name"]
	},
	{
		"name": "HaxeOutputPart",
		"define": "HAXE-OUTPUT-PART",
		"doc": "Output name of the executable/library. (default: main class name)",
		"platforms": ["cpp"],
		"params": ["name"]
	},
	{
		"name": "Hlc",
		"define": "hlc",
		"doc": "Defined by compiler when using hl/c target.",
		"platforms": ["hl"],
		"reserved": true
	},
	{
		"name": "HlVer",
		"define": "hl-ver",
		"doc": "The HashLink version to target. (default: 1.15.0)",
		"platforms": ["hl"],
		"params": ["version"]
	},
	{
		"name": "HxbTimes",
		"define": "times.hxb",
		"deprecatedDefine": "hxb-times",
		"signatureNeutral": true,
		"doc": "Display hxb timing when used with `--times`."
	},
	{
		"name": "HxbStats",
		"define": "hxb.stats",
		"signatureNeutral": true,
		"doc": "Display some hxb related stats (only with compilation server)."
	},
	{
		"name": "HxcppApiLevel",
		"define": "hxcpp-api-level",
		"doc": "Provided to allow compatibility between hxcpp versions.",
		"platforms": ["cpp"],
		"reserved": true
	},
	{
		"name": "HxcppGcGenerational",
		"define": "HXCPP-GC-GENERATIONAL",
		"doc": "Experimental Garbage Collector.",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppDebugger",
		"define": "HXCPP-DEBUGGER",
		"doc": "Include additional information for hxcpp-debugger.",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppGcMoving",
		"define": "HXCPP-GC-MOVING",
		"doc": "Allow garbage collector to move memory to reduce fragmentation",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppGcSummary",
		"define": "HXCPP-GC-SUMMARY",
		"doc": "Print small profiling summary at end of program",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppGcDynamicSize",
		"define": "HXCPP-GC-DYNAMIC-SIZE",
		"doc": "Monitor GC times and expand memory working space if required",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppGcBigBlocks",
		"define": "HXCPP-GC-BIG-BLOCKS",
		"doc": "Allow working memory greater than 1 Gig",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppGcDebugLevel",
		"define": "HXCPP-GC-DEBUG-LEVEL",
		"doc": "Number 1-4 indicating additional debugging in GC",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppDebugLink",
		"define": "HXCPP-DEBUG-LINK",
		"doc": "Add symbols to final binary, even in release mode.",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppStackTrace",
		"define": "HXCPP-STACK-TRACE",
		"doc": "Have valid function-level stack traces, even in release mode.",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppStackLine",
		"define": "HXCPP-STACK-LINE",
		"doc": "Include line information in stack traces, even in release mode.",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppCheckPointer",
		"define": "HXCPP-CHECK-POINTER",
		"doc": "Add null-pointer checks, even in release mode.",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppProfiler",
		"define": "HXCPP-PROFILER",
		"doc": "Add profiler support",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppTelemetry",
		"define": "HXCPP-TELEMETRY",
		"doc": "Add telemetry support",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppCpp11",
		"define": "HXCPP-CPP11",
		"doc": "Use C++11 features and link libraries",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppVerbose",
		"define": "HXCPP-VERBOSE",
		"doc": "Print extra output from build tool.",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppTimes",
		"define": "HXCPP-TIMES",
		"doc": "Show some basic profiling information",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppM32",
		"define": "HXCPP-M32",
		"doc": "Force 32-bit compile for current desktop",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppM64",
		"define": "HXCPP-M64",
		"doc": "Force 64-bit compile for current desktop",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppArm64",
		"define": "HXCPP-ARM64",
		"doc": "Compile arm-based devices for 64 bits",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppLinuxArm64",
		"define": "HXCPP-LINUX-ARM64",
		"doc": "Run on a linux ARM64 device",
		"platforms": ["cpp"]
	},
	{
		"name": "HxcppSmartStings",
		"define": "hxcpp-smart-strings",
		"doc": "Use wide strings in hxcpp. (Turned on by default unless `-D disable-unicode-strings` is specified.)",
		"platforms": ["cpp"]
	},
	{
		"name": "IncludePrefix",
		"define": "include-prefix",
		"doc": "Prepend path to generated include files.",
		"platforms": ["cpp"]
	},
	{
		"name": "Interp",
		"define": "interp",
		"doc": "The code is compiled to be run with `--interp`."
	},
	{
		"name": "JsClassic",
		"define": "js-classic",
		"doc": "Don't use a function wrapper and strict mode in JS output.",
		"platforms": ["js"]
	},
	{
		"name": "JsEs",
		"define": "js-es",
		"doc": "Generate JS compliant with given ES standard version. (default: 5)",
		"platforms": ["js"],
		"params": ["version: 3 | 5 | 6"],
		"links": ["https://haxe.org/manual/target-javascript-es6.html"]
	},
	{
		"name": "JsEnumsAsArrays",
		"define": "js-enums-as-arrays",
		"doc": "Generate enum representation as array instead of as object.",
		"platforms": ["js"]
	},
	{
		"name": "JsGlobal",
		"define": "js-global",
		"doc": "Customizes the global object name.",
		"platforms": ["js"]
	},
	{
		"name": "JsUnflatten",
		"define": "js-unflatten",
		"doc": "Generate nested objects for packages and types.",
		"platforms": ["js"]
	},
	{
		"name": "JsSourceMap",
		"define": "js-source-map",
		"doc": "Generate JavaScript source map even in non-debug mode. Deprecated in favor of `-D source-map`.",
		"platforms": ["js"]
	},
	{
		"name": "SourceMap",
		"define": "source-map",
		"doc": "Generate source map for compiled files.",
		"platforms": ["php", "js"]
	},
	{
		"name": "JvmCompressionLevel",
		"define": "jvm.compression-level",
		"doc": "Set the compression level of the generated file between 0 (no compression) and 9 (highest compression). Default: 6",
		"platforms": ["jvm"]
	},
	{
		"name": "JvmDynamicLevel",
		"define": "jvm.dynamic-level",
		"doc": "Controls the amount of dynamic support code being generated. 0 = none, 1 = field read/write optimization (default), 2 = compile-time method closures",
		"platforms": ["jvm"]
	},
	{
		"name": "LoopUnrollMaxCost",
		"define": "loop-unroll-max-cost",
		"doc": "Maximum cost (number of expressions * iterations) before loop unrolling is canceled. (default: 250)",
		"defaultValue": "250",
		"params": ["cost"]
	},
	{
		"name": "LuaJit",
		"define": "lua-jit",
		"doc": "Enable the jit compiler for lua (version 5.2 only).",
		"platforms": ["lua"]
	},
	{
		"name": "LuaVanilla",
		"define": "lua-vanilla",
		"doc": "Generate code lacking compiled extern lib support (e.g. utf8).",
		"platforms": ["lua"]
	},
	{
		"name": "LuaVer",
		"define": "lua-ver",
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
		"define": "times.macro",
		"deprecatedDefine": "macro-times",
		"signatureNeutral": true,
		"doc": "Display per-macro timing when used with `--times`."
	},
	{
		"name": "NekoSource",
		"define": "neko-source",
		"doc": "Output neko source instead of bytecode.",
		"platforms": ["neko"]
	},
	{
		"name": "NekoNoHaxelibPaths",
		"define": "neko-no-haxelib-paths",
		"doc": "Disable hard-coded Haxelib ndll paths.",
		"platforms": ["neko"]
	},
	{
		"name": "NekoV1",
		"define": "neko-v1",
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
		"signatureNeutral": true,
		"doc": "Disable final compilation.",
		"platforms": ["cpp", "hl"]
	},
	{
		"name": "NoDebug",
		"define": "no-debug",
		"doc": "Remove all debug macros from cpp output."
	},
	{
		"name": "NoDeprecationWarnings",
		"define": "no-deprecation-warnings",
		"doc": "Do not warn if fields annotated with `@:deprecated` are used.",
		"deprecated": "Use -w to configure warnings. See https://haxe.org/manual/cr-warnings.html for more information."
	},
	{
		"name": "NoFlashOverride",
		"define": "no-flash-override",
		"doc": "Change overrides on some basic classes into HX suffixed methods",
		"platforms": ["flash"]
	},
	{
		"name": "NoOpt",
		"define": "no-opt",
		"doc": "Disable optimizations."
	},
	{
		"name": "NoInline",
		"define": "no-inline",
		"doc": "Disable inlining.",
		"links": ["https://haxe.org/manual/class-field-inline.html"]
	},
	{
		"name": "KeepInlinePositions",
		"define": "keep-inline-positions",
		"doc": "Don't substitute positions of inlined expressions with the position of the place of inlining.",
		"links": ["https://haxe.org/manual/class-field-inline.html"]
	},
	{
		"name": "NoMacroCache",
		"define": "no-macro-cache",
		"doc": "Disable macro context caching."
	},
	{
		"name": "NoSwfCompress",
		"define": "no-swf-compress",
		"doc": "Disable SWF output compression.",
		"platforms": ["flash"]
	},
	{
		"name": "NoTraces",
		"define": "no-traces",
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
		"doc": "Use Haxe 3.x zero-based column error messages instead of new one-based format.",
		"deprecated": "OldErrorFormat has been removed in Haxe 5"
	},
	{
		"name": "PhpPrefix",
		"define": "php-prefix",
		"doc": "Root namespace for generated php classes. E.g. if compiled with`-D php-prefix=some.sub`, then all classes will be generated in `\\some\\sub` namespace.",
		"platforms": ["php"],
		"params": ["dot-separated namespace"]
	},
	{
		"name": "PhpLib",
		"define": "php-lib",
		"doc": "Select the name for the php lib folder.",
		"platforms": ["php"],
		"params": ["folder name"]
	},
	{
		"name": "PhpFront",
		"define": "php-front",
		"doc": "Select the name for the php front file. (default: `index.php`)",
		"platforms": ["php"],
		"params": ["filename"]
	},
	{
		"name": "PythonVersion",
		"define": "python-version",
		"doc": "The python version to target. (default: 3.3)",
		"platforms": ["python"],
		"params": ["version"]
	},
	{
		"name": "RealPosition",
		"define": "real-position",
		"doc": "Removes position comments in Php output.",
		"platforms": ["php"]
	},
	{
		"name": "RetainUntypedMeta",
		"define": "retain-untyped-meta",
		"doc": "Prevents arbitrary expression metadata from being discarded upon typing."
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
		"platforms": ["python"]
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
		"define": "swf-compress-level",
		"doc": "Set the amount of compression for the SWF output.",
		"platforms": ["flash"],
		"params": ["level: 1-9"]
	},
	{
		"name": "SwfDebugPassword",
		"define": "swf-debug-password",
		"doc": "Set a password for debugging.",
		"platforms": ["flash"],
		"params": ["password"]
	},
	{
		"name": "SwfDirectBlit",
		"define": "swf-direct-blit",
		"doc": "Use hardware acceleration to blit graphics.",
		"platforms": ["flash"]
	},
	{
		"name": "SwfGpu",
		"define": "swf-gpu",
		"doc": "Use GPU compositing features when drawing graphics.",
		"platforms": ["flash"]
	},
	{
		"name": "SwfHeader",
		"define": "swf-header",
		"doc": "define SWF header (width:height:fps:color)",
		"platforms": ["flash"]
	},
	{
		"name": "SwfMetadata",
		"define": "swf-metadata",
		"doc": "Include contents of the given file as metadata in the SWF.",
		"platforms": ["flash"],
		"params": ["file"]
	},
	{
		"name": "SwfPreloaderFrame",
		"define": "swf-preloader-frame",
		"doc": "Insert empty first frame in SWF.",
		"platforms": ["flash"]
	},
	{
		"name": "SwfProtected",
		"define": "swf-protected",
		"doc": "Compile Haxe `private` as `protected` in the SWF instead of `public`.",
		"platforms": ["flash"]
	},
	{
		"name": "SwfScriptTimeout",
		"define": "swf-script-timeout",
		"doc": "Maximum ActionScript processing time before script stuck dialog box displays.",
		"platforms": ["flash"],
		"params": ["time in seconds"]
	},
	{
		"name": "SwfUseDoAbc",
		"define": "swf-use-doabc",
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
		"name": "UseNekoc",
		"define": "use-nekoc",
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
		"define": "warn-var-shadowing",
		"doc": "Warn about shadowing variable declarations.",
		"deprecated": "Use -w to configure warnings. See https://haxe.org/manual/cr-warnings.html for more information."
	},
	{
		"name": "NoTre",
		"define": "no-tre",
		"doc": "Disable tail recursion elimination."
	},
	{
		"name": "MessageReporting",
		"define": "message.reporting",
		"signatureNeutral": true,
		"doc": "Select message reporting mode for compiler output. (default: pretty)",
		"defaultValue": "pretty",
		"params": ["mode: classic | pretty | indent"]
	},
	{
		"name": "MessageColor",
		"define": "message.color",
		"signatureNeutral": true,
		"doc": "Enable ANSI color codes in message reporting."
	},
	{
		"name": "MessageAbsolutePositions",
		"define": "message.absolute-positions",
		"signatureNeutral": true,
		"doc": "Use absolute character positions instead of line/columns for message reporting."
	},
	{
		"name": "MessageLogFile",
		"define": "message.log-file",
		"signatureNeutral": true,
		"doc": "Path to a text file to write message reporting to, in addition to regular output."
	},
	{
		"name": "MessageLogFormat",
		"define": "message.log-format",
		"signatureNeutral": true,
		"doc": "Select message reporting mode for message log file. (default: indent)",
		"defaultValue": "indent",
		"params": ["format: classic | pretty | indent"]
	}
];

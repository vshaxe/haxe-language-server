package haxeLanguageServer.features.hxml.data;

import haxeLanguageServer.features.hxml.data.Shared;

using Lambda;

typedef Flag = {
	final name:String;
	final ?shortName:String;
	final ?deprecatedNames:ReadOnlyArray<String>;
	final ?argument:{
		final name:String;
		final ?insertion:String;
		final ?kind:ArgumentKind;
	};
	var description:String;
}

enum ArgumentKind {
	Enum(values:EnumValues);
	Define;
	File;
	Directory;
	LibraryName;
}

enum Category {
	Target;
	Compilation;
	Optimization;
	Debug;
	Batch;
	Services;
	CompilationServer;
	TargetSpecific;
	Miscellaneous;
}

final HxmlFlags = {
	final flags:Map<Category, ReadOnlyArray<Flag>> = [
		Target => [
			{
				name: "--js",
				deprecatedNames: ["-js"],
				argument: {
					name: "<file>",
					insertion: "bin/${1:main}.js",
					kind: File
				},
				description: "generate JavaScript code into target file"
			},
			{
				name: "--lua",
				deprecatedNames: ["-lua"],
				argument: {
					name: "<file>",
					insertion: "bin/${1:main}.lua",
					kind: File
				},
				description: "generate Lua code into target file"
			},
			{
				name: "--swf",
				deprecatedNames: ["-swf"],
				argument: {
					name: "<file>",
					insertion: "bin/${1:main}.swf",
					kind: File
				},
				description: "generate Flash SWF bytecode into target file"
			},
			{
				name: "--neko",
				deprecatedNames: ["-neko"],
				argument: {
					name: "<file>",
					insertion: "bin/${1:main}.n",
					kind: File
				},
				description: "generate Neko bytecode into target file"
			},
			{
				name: "--php",
				deprecatedNames: ["-php"],
				argument: {
					name: "<directory>",
					insertion: "bin/php",
					kind: Directory
				},
				description: "generate PHP code into target directory"
			},
			{
				name: "--cpp",
				deprecatedNames: ["-cpp"],
				argument: {
					name: "<directory>",
					insertion: "bin/cpp",
					kind: Directory
				},
				description: "generate C++ code into target directory"
			},
			{
				name: "--cppia",
				deprecatedNames: ["-cppia"],
				argument: {
					name: "<file>",
					insertion: "bin/${1:main}.cppia",
					kind: File
				},
				description: "generate Cppia bytecode into target file"
			},
			{
				name: "--cs",
				deprecatedNames: ["-cs"],
				argument: {
					name: "<directory>",
					insertion: "bin/cs",
					kind: Directory
				},
				description: "generate C# code into target directory"
			},
			{
				name: "--java",
				deprecatedNames: ["-java"],
				argument: {
					name: "<directory>",
					insertion: "bin/java",
					kind: Directory
				},
				description: "generate Java code into target directory"
			},
			{
				name: "--jvm",
				deprecatedNames: ["-jvm"],
				argument: {
					name: "<file>",
					insertion: "bin/${1:main}.jar",
					kind: File
				},
				description: "generate JVM bytecode into target file"
			},
			{
				name: "--python",
				deprecatedNames: ["-python"],
				argument: {
					name: "<file>",
					insertion: "bin/${1:main}.py",
					kind: File
				},
				description: "generate Python code into target file"
			},
			{
				name: "--hl",
				deprecatedNames: ["-hl"],
				argument: {
					name: "<file>",
					insertion: "bin/${1:main}.hl",
					kind: File
				},
				description: "generate HashLink `.hl` bytecode or `.c` code into target file"
			},
			{
				name: "--interp",
				deprecatedNames: ["-interp"],
				description: "interpret the program using internal macro system"
			},
			{
				name: "--run",
				argument: {
					name: "<module> [args...]",
					insertion: "Main"
				},
				description: "interpret a Haxe module with command line arguments"
			}
		],
		// Compilation
		Compilation => [
			{
				name: "--class-path",
				shortName: "-p",
				deprecatedNames: ["-cp"],
				argument: {
					name: "<path>",
					kind: Directory
				},
				description: "add a directory to find source files"
			},
			{
				name: "--main",
				shortName: "-m",
				deprecatedNames: ["-main"],
				argument: {
					name: "<class>",
					insertion: "Main"
				},
				description: "select startup class"
			},
			{
				name: "--library",
				shortName: "-L",
				deprecatedNames: ["-lib"],
				argument: {
					name: "<name[:ver]>",
					kind: LibraryName
				},
				description: "use a haxelib library"
			},
			{
				name: "--define",
				shortName: "-D",
				argument: {
					name: "<var[=value]>",
					kind: Define
				},
				description: "define a conditional compilation flag"
			},
			{
				name: "--resource",
				shortName: "-r",
				deprecatedNames: ["-resource"],
				argument: {
					name: "<file>[@name]",
					kind: File
				},
				description: "define a conditional compilation flag"
			},
			{
				name: "--cmd",
				deprecatedNames: ["-cmd"],
				argument: {
					name: "<command>",
					insertion: "command"
				},
				description: "run the specified command after successful compilation"
			},
			{
				name: "--remap",
				argument: {
					name: "<package:target>",
					insertion: "${1:package}:${2:target}"
				},
				description: "remap a package to another one"
			},
			{
				name: "--macro",
				argument: {
					name: "<macro>",
					insertion: "macro"
				},
				description: "call the given macro before typing anything else"
			},
			{
				name: "--cwd",
				shortName: "-C",
				argument: {
					name: "<directory>",
					kind: Directory
				},
				description: "set current working directory"
			},
			{
				name: "--haxelib-global",
				description: "pass `--global` argument to haxelib"
			}
		],
		Optimization => [
			{
				name: "--dce",
				deprecatedNames: ["-dce"],
				argument: {
					name: "[std|full|no]",
					kind: Enum(DceEnumValues)
				},
				description: "set the dead code elimination mode (default `std`)"
			},
			{
				name: "--no-traces",
				description: "don't compile trace calls in the program"
			},
			{
				name: "--no-output",
				description: "compiles but does not generate any file"
			},
			{
				name: "--no-inline",
				description: "disable inlining"
			},
			{
				name: "--no-opt",
				description: "disable code optimizations"
			}
		],
		Debug => [
			{
				name: "--verbose",
				shortName: "-v",
				description: "turn on verbose mode"
			},
			{
				name: "--debug",
				deprecatedNames: ["-debug"],
				description: "add debug information to the compiled code"
			},
			// `prompt` omitted; doesn't seem too useful in hxml
			{
				name: "--times",
				description: "measure compilation times"
			}
		],
		Batch => [
			{
				name: "--next",
				description: "separate several haxe compilations"
			},
			{
				name: "--each",
				description: "append preceding parameters to all Haxe compilations separated by `--next`"
			}
		],
		Services => [
			// `display` omitted; doesn't seem too useful in hxml
			{
				name: "--xml",
				deprecatedNames: ["-xml"],
				argument: {
					name: "<file>",
					insertion: "bin/${1:types}.xml",
					kind: File
				},
				description: "generate XML types description"
			},
			{
				name: "--json",
				argument: {
					name: "<file>",
					insertion: "bin/${1:types}.json",
					kind: File
				},
				description: "generate JSON types description"
			}
		],
		CompilationServer => [
			{
				name: "--connect",
				argument: {
					name: "<[host:]port>",
					insertion: "7000"
				},
				description: "connect on the given port and run commands there"
			},
			// `server-listen` and `server-connect` omitted; doesn't seem too useful in hxml
		],
		TargetSpecific => [
			{
				name: "--swf-version",
				argument: {
					name: "<version>",
					kind: Enum([
						9., 10., 10.1, 10.2, 10.3, 11., 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 11.7, 11.8, 11.9, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0,
						20.0, 21.0, 22.0, 23.0, 24.0, 25.0, 26.0, 27.0, 28.0, 29.0, 31.0, 32.0
					].map(version -> {
						name: Std.string(version),
						description: null
					})),
				},
				description: "change the SWF version"
			},
			{
				name: "--swf-header",
				argument: {
					name: "<header>",
					insertion: "${1:width}:${2:height}:${3:fps}:${4:color}"
				},
				description: "define SWF header (`width:height:fps:color`)"
			},
			{
				name: "--flash-strict",
				description: "more type strict flash API"
			},
			{
				name: "--swf-lib",
				argument: {
					name: "<file>",
					kind: File
				},
				description: "add the SWF library to the compiled SWF"
			},
			{
				name: "--swf-lib-extern",
				argument: {
					name: "<file>",
					kind: File
				},
				description: "use the SWF library for type checking"
			},
			{
				name: "--java-lib",
				argument: {
					name: "<file>",
					kind: File
				},
				description: "add an external JAR or directory of JAR files"
			},
			{
				name: "--java-lib-extern",
				argument: {
					name: "<file>",
					kind: File
				},
				description: "use an external JAR or directory of JAR files for type checking"
			},
			{
				name: "--net-lib",
				argument: {
					name: "<file>[@std]",
					kind: File
				},
				description: "add an external .NET DLL file"
			},
			{
				name: "--net-std",
				argument: {
					name: "<file>",
					kind: File
				},
				description: "add a root std .NET DLL search path"
			},
			{
				name: "--c-arg",
				argument: {
					name: "<arg>",
					insertion: "arg"
				},
				description: "pass option `<arg>` to the native Java/C# compiler"
			}
		],
		// omitted; doesn't seem too useful in hxml
		Miscellaneous => []
	];
	for (flag in flags.flatten()) {
		flag.description = flag.description.capitalize() + ".";
	}
	flags;
}

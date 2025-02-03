package haxeLanguageServer;

import haxe.DynamicAccess;
import haxe.Json;
import haxe.extern.EitherType;
import haxeLanguageServer.helper.StructDefaultsMacro;
import jsonrpc.Protocol;

typedef HaxelibConfig = {
	var executable:String;
}

typedef FunctionFormattingConfig = {
	var argumentTypeHints:Bool;
	var returnTypeHint:ReturnTypeHintOption;
	var useArrowSyntax:Bool;
	var placeOpenBraceOnNewLine:Bool;
	var explicitPublic:Bool;
	var explicitPrivate:Bool;
	var explicitNull:Bool;
}

enum abstract ReturnTypeHintOption(String) {
	final Always = "always";
	final Never = "never";
	final NonVoid = "non-void";
}

private typedef FunctionGenerationConfig = {
	var anonymous:FunctionFormattingConfig;
	var field:FunctionFormattingConfig;
}

enum abstract ImportStyle(String) {
	final Module = "module";
	final Type = "type";
}

private typedef ImportGenerationConfig = {
	var enableAutoImports:Bool;
	var style:ImportStyle;
}

private typedef SwitchGenerationConfig = {
	var parentheses:Bool;
}

private typedef CodeGenerationConfig = {
	var functions:FunctionGenerationConfig;
	var imports:ImportGenerationConfig;
	var switch_:SwitchGenerationConfig;
}

private typedef PostfixCompletionConfig = {
	var level:PostfixCompletionLevel;
}

private enum abstract PostfixCompletionLevel(String) {
	final Full = "full";
	final Filtered = "filtered";
	final Off = "off";
}

enum abstract ImportsSortOrderConfig(String) {
	final AllAlphabetical = "all-alphabetical";
	final StdlibThenLibsThenProject = "stdlib -> libs -> project";
	final NonProjectThenProject = "non-project -> project";
}

private typedef InlayHintConfig = {
	var variableTypes:Bool;
	var parameterNames:Bool;
	var parameterTypes:Bool;
	var functionReturnTypes:Bool;
	var conditionals:Bool;
}

typedef ServerRecordingConfig = {
	var enabled:Bool;
	var path:String;
	var exclude:Array<String>;
	var excludeUntracked:Bool;
	var watch:Array<String>;
}

typedef UserConfig = {
	var enableCodeLens:Bool;
	var enableDiagnostics:Bool;
	var enableServerView:Bool;
	var enableSignatureHelpDocumentation:Bool;
	var diagnosticsForAllOpenFiles:Bool;
	var diagnosticsPathFilter:String;
	var displayHost:String;
	var displayPort:EitherType<Int, String>;
	var buildCompletionCache:Bool;
	var enableCompletionCacheWarning:Bool;
	var useLegacyCompletion:Bool;
	var useLegacyDiagnostics:Bool;
	var codeGeneration:CodeGenerationConfig;
	var exclude:Array<String>;
	var postfixCompletion:PostfixCompletionConfig;
	var importsSortOrder:ImportsSortOrderConfig;
	var maxCompletionItems:Int;
	var renameSourceFolders:Array<String>;
	var disableRefactorCache:Bool;
	var disableInlineValue:Bool;
	var inlayHints:InlayHintConfig;
	var serverRecording:ServerRecordingConfig;
}

typedef ExperimentalCapabilities = {
	/**
		List of supported commands on client, like `"codeAction.insertSnippet"`,
		to generate snippets in code actions, instead of simple text edits
	**/
	var ?supportedCommands:Array<String>;

	/** Forces resolve support for code actions `command` property **/
	var ?forceCommandResolveSupport:Bool;
}

typedef InitOptions = {
	var displayServerConfig:DisplayServerConfig;
	var displayArguments:Array<String>;
	var haxelibConfig:HaxelibConfig;
	var sendMethodResults:Bool;
	var experimentalClientCapabilities:ExperimentalCapabilities;
}

enum ConfigurationKind {
	User;
	DisplayArguments;
	DisplayServer;
}

class Configuration {
	static final DefaultInitOptions:InitOptions = {
		displayServerConfig: {
			path: "haxe",
			env: new DynamicAccess(),
			arguments: [],
			print: {
				completion: false,
				reusing: false
			},
			useSocket: true
		},
		displayArguments: [],
		haxelibConfig: {
			executable: "haxelib"
		},
		sendMethodResults: false,
		experimentalClientCapabilities: {
			supportedCommands: []
		}
	};

	static final DefaultUserSettings:UserConfig = {
		enableCodeLens: false,
		enableDiagnostics: true,
		enableServerView: false,
		enableSignatureHelpDocumentation: true,
		diagnosticsForAllOpenFiles: true,
		diagnosticsPathFilter: "${workspaceRoot}",
		displayHost: null,
		displayPort: null,
		buildCompletionCache: true,
		enableCompletionCacheWarning: true,
		useLegacyCompletion: false,
		useLegacyDiagnostics: false,
		codeGeneration: {
			functions: {
				anonymous: {
					argumentTypeHints: false,
					returnTypeHint: Never,
					useArrowSyntax: true,
					placeOpenBraceOnNewLine: false,
					explicitPublic: false,
					explicitPrivate: false,
					explicitNull: false
				},
				field: {
					argumentTypeHints: true,
					returnTypeHint: NonVoid,
					useArrowSyntax: false,
					placeOpenBraceOnNewLine: false,
					explicitPublic: false,
					explicitPrivate: false,
					explicitNull: false,
				}
			},
			imports: {
				style: Type,
				enableAutoImports: true
			},
			switch_: {
				parentheses: false
			}
		},
		exclude: ["zpp_nape"],
		postfixCompletion: {
			level: Full
		},
		importsSortOrder: AllAlphabetical,
		maxCompletionItems: 1000,
		renameSourceFolders: ["src", "source", "Source", "test", "tests"],
		disableRefactorCache: false,
		disableInlineValue: true,
		inlayHints: {
			variableTypes: false,
			parameterNames: false,
			parameterTypes: false,
			functionReturnTypes: false,
			conditionals: false
		},
		serverRecording: {
			enabled: false,
			path: ".haxelsp/recording/",
			exclude: [],
			excludeUntracked: false,
			watch: []
		}
	};

	final onDidChange:(kind:ConfigurationKind) -> Void;
	var unmodifiedUserConfig:Null<UserConfig>;

	@:nullSafety(Off) public var user(default, null):UserConfig;
	@:nullSafety(Off) public var displayServer(default, null):DisplayServerConfig;
	@:nullSafety(Off) public var displayArguments(default, null):Array<String>;
	@:nullSafety(Off) public var haxelib(default, null):HaxelibConfig;
	public var sendMethodResults(default, null):Bool = false;

	public function new(languageServerProtocol:Protocol, onDidChange:(kind:ConfigurationKind) -> Void) {
		this.onDidChange = onDidChange;

		languageServerProtocol.onNotification(DidChangeConfigurationNotification.type, onDidChangeConfiguration);
		languageServerProtocol.onNotification(LanguageServerMethods.DidChangeDisplayArguments, onDidChangeDisplayArguments);
		languageServerProtocol.onNotification(LanguageServerMethods.DidChangeDisplayServerConfig, onDidChangeDisplayServerConfig);
	}

	public function onInitialize(params:InitializeParams) {
		var options:Null<InitOptions> = params.initializationOptions;
		StructDefaultsMacro.applyDefaults(options, DefaultInitOptions);
		displayServer = options.displayServerConfig;
		displayArguments = options.displayArguments;
		haxelib = options.haxelibConfig;
		sendMethodResults = options.sendMethodResults;
	}

	function onDidChangeConfiguration(newConfig:DidChangeConfigurationParams) {
		final initialized = user != null;
		var newHaxeConfig = newConfig.settings.haxe;
		if (newHaxeConfig == null) {
			newHaxeConfig = {};
		}

		final newConfigJson = Json.stringify(newHaxeConfig);
		final configUnchanged = unmodifiedUserConfig != null && Json.stringify(unmodifiedUserConfig) == newConfigJson;
		if (initialized && configUnchanged) {
			return;
		}
		unmodifiedUserConfig = Json.parse(newConfigJson);

		processSettings(newHaxeConfig);
		onDidChange(User);
	}

	function processSettings(newConfig:Dynamic) {
		// this is a hacky way to completely ignore uninteresting config sections
		// to do this properly, we need to make language server not watch the whole haxe.* section,
		// but only what's interesting for us
		Reflect.deleteField(newConfig, "displayServer");
		Reflect.deleteField(newConfig, "displayConfigurations");
		Reflect.deleteField(newConfig, "configurations");
		Reflect.deleteField(newConfig, "executable");

		user = newConfig;

		// work around `switch` being a keyword
		if (newConfig.codeGeneration != null) {
			newConfig.codeGeneration.switch_ = Reflect.field(newConfig.codeGeneration, "switch");
			Reflect.deleteField(newConfig.codeGeneration, "switch");
		}

		StructDefaultsMacro.applyDefaults(user, DefaultUserSettings);
	}

	function onDidChangeDisplayArguments(params:{arguments:Array<String>}) {
		displayArguments = params.arguments;
		onDidChange(DisplayArguments);
	}

	function onDidChangeDisplayServerConfig(config:DisplayServerConfig) {
		displayServer = config;
		onDidChange(DisplayServer);
	}
}

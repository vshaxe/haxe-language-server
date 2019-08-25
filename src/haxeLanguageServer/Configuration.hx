package haxeLanguageServer;

import haxe.Json;
import jsonrpc.Protocol;
import haxe.extern.EitherType;
import haxeLanguageServer.helper.StructDefaultsMacro;
import haxe.display.Server.ConfigurePrintParams;

typedef DisplayServerConfig = {
	var ?path:String;
	var ?env:haxe.DynamicAccess<String>;
	var ?arguments:Array<String>;
	var ?print:ConfigurePrintParams;
}

typedef HaxelibConfig = {
	var ?executable:String;
}

typedef FunctionFormattingConfig = {
	var ?argumentTypeHints:Bool;
	var ?returnTypeHint:ReturnTypeHintOption;
	var ?useArrowSyntax:Bool;
	var ?placeOpenBraceOnNewLine:Bool;
	var ?explicitPublic:Bool;
	var ?explicitPrivate:Bool;
	var ?explicitNull:Bool;
}

enum abstract ReturnTypeHintOption(String) {
	var Always = "always";
	var Never = "never";
	var NonVoid = "non-void";
}

private typedef FunctionGenerationConfig = {
	var ?anonymous:FunctionFormattingConfig;
	var ?field:FunctionFormattingConfig;
}

enum abstract ImportStyle(String) {
	var Module = "module";
	var Type = "type";
}

private typedef ImportGenerationConfig = {
	var ?enableAutoImports:Bool;
	var ?style:ImportStyle;
}

private typedef SwitchGenerationConfig = {
	var ?parentheses:Bool;
}

private typedef CodeGenerationConfig = {
	var ?functions:FunctionGenerationConfig;
	var ?imports:ImportGenerationConfig;
	var ?switch_:SwitchGenerationConfig;
}

private typedef PostfixCompletionConfig = {
	var ?level:PostfixCompletionLevel;
}

private enum abstract PostfixCompletionLevel(String) {
	var Full = "full";
	var Filtered = "filtered";
	var Off = "off";
}

private typedef UserConfig = {
	var ?enableCodeLens:Bool;
	var ?enableDiagnostics:Bool;
	var ?enableServerView:Bool;
	var ?enableSignatureHelpDocumentation:Bool;
	var ?diagnosticsPathFilter:String;
	var ?displayPort:EitherType<Int, String>;
	var ?buildCompletionCache:Bool;
	var ?enableCompletionCacheWarning:Bool;
	var ?codeGeneration:CodeGenerationConfig;
	var ?exclude:Array<String>;
	var ?postfixCompletion:PostfixCompletionConfig;
}

private typedef InitOptions = {
	var ?displayServerConfig:DisplayServerConfig;
	var ?displayArguments:Array<String>;
	var ?haxelibConfig:HaxelibConfig;
	var ?sendMethodResults:Bool;
}

enum ConfigurationKind {
	User;
	DisplayArguments;
	DisplayServer;
}

class Configuration {
	final onDidChange:(kind:ConfigurationKind) -> Void;
	var unmodifiedUserConfig:UserConfig;

	public var user(default, null):UserConfig;
	public var displayServer(default, null):DisplayServerConfig;
	public var displayArguments(default, null):Array<String>;
	public var haxelib(default, null):HaxelibConfig;
	public var sendMethodResults(default, null):Bool = false;

	public function new(languageServerProtocol:Protocol, onDidChange:(kind:ConfigurationKind) -> Void) {
		this.onDidChange = onDidChange;

		languageServerProtocol.onNotification(DidChangeConfigurationNotification.type, onDidChangeConfiguration);
		languageServerProtocol.onNotification(LanguageServerMethods.DidChangeDisplayArguments, onDidChangeDisplayArguments);
		languageServerProtocol.onNotification(LanguageServerMethods.DidChangeDisplayServerConfig, onDidChangeDisplayServerConfig);
	}

	public function onInitialize(params:InitializeParams) {
		var options:InitOptions = params.initializationOptions;
		var defaults:InitOptions = {
			displayServerConfig: {
				path: "haxe",
				env: new haxe.DynamicAccess(),
				arguments: [],
				print: {
					completion: false,
					reusing: false
				}
			},
			displayArguments: [],
			haxelibConfig: {
				executable: "haxelib"
			},
			sendMethodResults: false
		};
		StructDefaultsMacro.applyDefaults(options, defaults);
		displayServer = options.displayServerConfig;
		displayArguments = options.displayArguments;
		haxelib = options.haxelibConfig;
		sendMethodResults = options.sendMethodResults;
	}

	function onDidChangeConfiguration(newConfig:DidChangeConfigurationParams) {
		var initialized = user != null;
		var newHaxeConfig = newConfig.settings.haxe;
		if (newHaxeConfig == null) {
			newHaxeConfig = {};
		}

		var newConfigJson = Json.stringify(newHaxeConfig);
		var configUnchanged = Json.stringify(unmodifiedUserConfig) == newConfigJson;
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

		var defaults:UserConfig = {
			enableCodeLens: false,
			enableDiagnostics: true,
			enableServerView: false,
			enableSignatureHelpDocumentation: true,
			diagnosticsPathFilter: "${workspaceRoot}",
			displayPort: null,
			buildCompletionCache: true,
			enableCompletionCacheWarning: true,
			codeGeneration: {
				functions: {
					anonymous: {
						returnTypeHint: Never,
						argumentTypeHints: false,
						useArrowSyntax: true,
						explicitNull: false,
					},
					field: {
						returnTypeHint: NonVoid,
						argumentTypeHints: true,
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
			}
		};
		StructDefaultsMacro.applyDefaults(user, defaults);
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

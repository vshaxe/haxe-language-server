package haxeLanguageServer;

using StringTools;

function shellEscapeCommand(command:String):String {
	if (!~/[^a-zA-Z0-9_.:\/\\-]/.match(command)) {
		return command;
	}
	if (command.startsWith('"') && command.endsWith('"')) {
		return command;
	}

	return '"' + command.replace('"', '\\"') + '"';
}

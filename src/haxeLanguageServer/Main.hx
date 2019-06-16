package haxeLanguageServer;

import js.Node.process;
import jsonrpc.node.MessageReader;
import jsonrpc.node.MessageWriter;
import jsonrpc.Protocol;

class Main {
	static function main() {
		var reader = new MessageReader(process.stdin);
		var writer = new MessageWriter(process.stdout);
		var languageServerProtocol = new Protocol(writer.write);
		languageServerProtocol.logError = message -> languageServerProtocol.sendNotification(Methods.LogMessage, {type: Warning, message: message});
		setupTrace(languageServerProtocol);
		var context = new Context(languageServerProtocol);
		reader.listen(languageServerProtocol.handleMessage);

		languageServerProtocol.didRespondToRequest = function(request, response) {
			if (context.config.sendMethodResults) {
				languageServerProtocol.sendNotification(LanguageServerMethods.DidRunHaxeMethod, {
					method: request.method,
					debugInfo: null,
					response: {
						result: {
							request: request,
							response: response
						}
					}
				});
			}
		};
	}

	static function setupTrace(languageServerProtocol:Protocol) {
		haxe.Log.trace = function(v, ?i) {
			var r = [Std.string(v)];
			if (i != null && i.customParams != null) {
				for (v in i.customParams)
					r.push(Std.string(v));
			}
			languageServerProtocol.sendNotification(Methods.LogMessage, {type: Log, message: r.join(" ")});
		}
	}
}

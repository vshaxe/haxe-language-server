package haxeLanguageServer;

import js.Node.process;
import jsonrpc.Protocol;
import jsonrpc.node.MessageReader;
import jsonrpc.node.MessageWriter;

function main() {
	var reader = new MessageReader(process.stdin);
	var writer = new MessageWriter(process.stdout);
	var languageServerProtocol = new Protocol(writer.write);
	languageServerProtocol.logError = message -> languageServerProtocol.sendNotification(LogMessageNotification.type, {type: Warning, message: message});
	setupTrace(languageServerProtocol);
	var context = new Context(languageServerProtocol);
	reader.listen(languageServerProtocol.handleMessage);

	function log(method:String, data:Dynamic) {
		if (context.config.sendMethodResults) {
			languageServerProtocol.sendNotification(LanguageServerMethods.DidRunMethod, {
				kind: Lsp,
				method: method,
				debugInfo: null,
				response: {
					result: data
				}
			});
		}
	}
	languageServerProtocol.didRespondToRequest = function(request, response) {
		log(request.method, {
			request: request,
			response: response
		});
	}
	languageServerProtocol.didSendNotification = function(notification) {
		if (notification.method != LogMessageNotification.type && !notification.method.startsWith("haxe/")) {
			log(notification.method, notification);
		}
	}
}

private function setupTrace(languageServerProtocol:Protocol) {
	haxe.Log.trace = function(v, ?i) {
		var r = [Std.string(v)];
		if (i != null && i.customParams != null) {
			for (v in i.customParams)
				r.push(Std.string(v));
		}
		languageServerProtocol.sendNotification(LogMessageNotification.type, {type: Log, message: r.join(" ")});
	}
}

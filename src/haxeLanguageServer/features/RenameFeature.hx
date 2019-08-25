package haxeLanguageServer.features;

import haxeLanguageServer.hxParser.RenameResolver;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

class RenameFeature {
	final context:Context;

	public function new(context:Context) {
		this.context = context;
		context.languageServerProtocol.onRequest(RenameRequest.type, onRename);
	}

	function onRename(params:RenameParams, token:CancellationToken, resolve:WorkspaceEdit->Void, reject:ResponseError<NoData>->Void) {
		if (!params.textDocument.uri.isFile()) {
			return reject.notAFile();
		}

		if (!~/[_A-Za-z]\w*/.match(params.newName)) {
			return reject(ResponseError.internalError("'" + params.newName + "' is not a valid identifier name."));
		}

		function invalidRename() {
			reject(ResponseError.internalError("Only local variables and function parameters can be renamed."));
		}

		context.gotoDefinition.onGotoDefinition(params, token, locations -> {
			var doc = context.documents.get(params.textDocument.uri);
			var declaration = locations[0];
			if (declaration == null) {
				return reject(ResponseError.internalError("No declaration found."));
			}
			if (declaration.uri != params.textDocument.uri) {
				return invalidRename();
			}

			var resolver = new RenameResolver(declaration.range, params.newName);
			resolver.walkFile(doc.parseTree, Root);
			if (resolver.edits.length == 0) {
				return invalidRename();
			}

			var changes = new haxe.DynamicAccess();
			changes[params.textDocument.uri.toString()] = resolver.edits;
			resolve({changes: changes});
		}, _ -> invalidRename());
	}
}

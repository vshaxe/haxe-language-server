package haxeLanguageServer.features.haxe.codeAction.diagnostics;

import js.lib.Promise;
import jsonrpc.CancellationToken;
import languageServerProtocol.Types.DefinitionLink;
import tokentree.TokenTree;

class ChangeFinalToVarAction {
	public static function createChangeFinalToVarAction(context:Context, action:CodeAction, params:CodeActionParams,
			diagnostic:Diagnostic):Null<Promise<CodeAction>> {
		if ((params.context.only != null) && (!params.context.only.contains(QuickFix))) {
			return null;
		}
		final document = context.documents.getHaxe(params.textDocument.uri);
		if (document == null || diagnostic.range == null)
			return null;
		var tokenSource = new CancellationTokenSource();

		final varToken = document.tokens?.getTokenAtOffset(document.offsetAt(diagnostic.range.start));
		if (varToken == null)
			return null;
		final gotoPromise = new Promise(function(resolve:(definitions:Array<DefinitionLink>) -> Void, reject) {
			context.gotoDefinition.onGotoDefinition({
				textDocument: params.textDocument,
				position: document.positionAt(varToken.pos.min, Utf8)
			}, tokenSource.token, array -> {
				resolve(array);
			}, error -> reject(error));
		});

		final actionPromise = Promise.all([gotoPromise]).then(results -> {
			final definitions:Array<DefinitionLink> = results[0];
			final definition = definitions[0] ?? return action;
			final definitionDoc = context.documents.getHaxe(definition.targetUri);
			if (definitionDoc == null)
				return action;
			final varDefinitionToken = definitionDoc.tokens?.getTokenAtOffset(definitionDoc.offsetAt(definition.targetSelectionRange.start));
			final kwdFinal = getFinalKwd(varDefinitionToken) ?? return action;
			final range = document.rangeAt(kwdFinal.pos.min, kwdFinal.pos.max, Utf8);
			action.edit = WorkspaceEditHelper.create(definitionDoc, [{range: range, newText: "var"}]);
			return action;
		});
		return actionPromise;
	}

	static function getFinalKwd(token:Null<TokenTree>) {
		final kwdFinal = token?.parent;
		if (kwdFinal == null)
			return null;
		if (!kwdFinal.tok.match(Kwd(KwdFinal)))
			return null;
		return kwdFinal;
	}
}

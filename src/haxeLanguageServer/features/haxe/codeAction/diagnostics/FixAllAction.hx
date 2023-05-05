package haxeLanguageServer.features.haxe.codeAction.diagnostics;

import languageServerProtocol.Types.CodeAction;

class FixAllAction {
	public static function createFixAllAction(context:Context, params:CodeActionParams, existingActions:Array<CodeAction>):Array<CodeAction> {
		if ((params.context.only != null) && (!params.context.only.contains(SourceFixAll))) {
			return [];
		}
		final uri = params.textDocument.uri;
		final doc = context.documents.getHaxe(uri);
		if (doc == null) {
			return [];
		}

		final action:CodeAction = {
			title: DiagnosticsFeature.FixAllTitle,
			kind: SourceFixAll,
			command: {
				title: DiagnosticsFeature.FixAllTitle,
				command: "haxe.fixAll"
			},
			isPreferred: true
		}

		return [action];
	}
}

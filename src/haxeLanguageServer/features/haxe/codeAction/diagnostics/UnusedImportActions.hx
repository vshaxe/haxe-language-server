package haxeLanguageServer.features.haxe.codeAction.diagnostics;

import haxeLanguageServer.features.haxe.DiagnosticsFeature.*;
import haxeLanguageServer.helper.DocHelper;

class UnusedImportActions {
	public static function createUnusedImportActions(context:Context, params:CodeActionParams, diagnostic:Diagnostic):Array<CodeAction> {
		if ((params.context.only != null) && (!params.context.only.contains(QuickFix))) {
			return [];
		}
		final doc = context.documents.getHaxe(params.textDocument.uri);
		if (doc == null || diagnostic.range == null) {
			return [];
		}
		return [
			{
				title: DiagnosticsFeature.RemoveUnusedImportUsingTitle,
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, [
					{
						range: DocHelper.untrimRange(doc, diagnostic.range.sure()),
						newText: ""
					}
				]),
				diagnostics: [diagnostic],
				isPreferred: true
			}
		];
	}
}

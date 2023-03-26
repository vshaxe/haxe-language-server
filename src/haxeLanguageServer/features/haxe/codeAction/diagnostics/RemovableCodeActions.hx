package haxeLanguageServer.features.haxe.codeAction.diagnostics;

class RemovableCodeActions {
	public static function createRemovableCodeActions(context:Context, params:CodeActionParams, diagnostic:Diagnostic):Array<CodeAction> {
		if ((params.context.only != null) && (!params.context.only.contains(QuickFix))) {
			return [];
		}
		final range = context.diagnostics.getArguments(params.textDocument.uri, RemovableCode, diagnostic.range)!.range;
		if (range == null) {
			return [];
		}
		return [
			{
				title: "Remove",
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, @:nullSafety(Off) [{range: range, newText: ""}]),
				diagnostics: [diagnostic],
				isPreferred: true
			}
		];
	}
}

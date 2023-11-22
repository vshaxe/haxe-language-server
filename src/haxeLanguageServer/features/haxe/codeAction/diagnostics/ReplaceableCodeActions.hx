package haxeLanguageServer.features.haxe.codeAction.diagnostics;

class ReplaceableCodeActions {
	public static function createReplaceableCodeActions(context:Context, params:CodeActionParams, diagnostic:Diagnostic):Array<CodeAction> {
		if ((params.context.only != null) && (!params.context.only.contains(QuickFix))) {
			return [];
		}
		final args = context.diagnostics.getArguments(params.textDocument.uri, ReplaceableCode, diagnostic.range);
		final range = args!.range;
		final newText = args!.newCode;
		if (range == null) {
			return [];
		}
		return [
			{
				title: newText == null || newText == "" ? "Remove" : 'Replace with $newText',
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, @:nullSafety(Off) [
					{
						range: range,
						newText: newText
					}
				]),
				diagnostics: [diagnostic],
				isPreferred: true
			}
		];
	}
}

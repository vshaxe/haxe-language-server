package haxeLanguageServer.features.haxe.codeAction.diagnostics;

import haxe.display.Diagnostic.DiagnosticKind;
import haxeLanguageServer.features.haxe.codeAction.CodeActionFeature;
import haxeLanguageServer.features.haxe.codeAction.OrganizeImportsFeature;
import haxeLanguageServer.helper.DocHelper;
import languageServerProtocol.Types.CodeAction;

class OrganizeImportActions {
	public static function createOrganizeImportActions(context:Context, params:CodeActionParams, existingActions:Array<CodeAction>):Array<CodeAction> {
		var shouldQuickFix:Bool = true;
		var shouldOrganize:Bool = true;
		var shouldSort:Bool = true;

		if (params.context.only != null) {
			shouldQuickFix = params.context.only.contains(QuickFix);
			shouldOrganize = params.context.only.contains(SourceOrganizeImports);
			shouldSort = params.context.only.contains(CodeActionFeature.SourceSortImports);
		}
		if (!shouldQuickFix && !shouldOrganize && !shouldSort) {
			return [];
		}

		final uri = params.textDocument.uri;
		final doc = context.documents.getHaxe(uri);
		if (doc == null) {
			return [];
		}
		final map = context.diagnostics.getArgumentsMap(uri);
		final removeUnusedFixes = if (map == null) [] else [
			for (key in map.keys()) {
				if (key.code == DiagnosticKind.DKUnusedImport && key.range != null) {
					WorkspaceEditHelper.removeText(DocHelper.untrimRange(doc, key.range));
				}
			}
		];

		final sortFixes = OrganizeImportsFeature.organizeImports(doc, context, []);

		final unusedRanges:Array<Range> = removeUnusedFixes.map(edit -> edit.range);
		final organizeFixes = removeUnusedFixes.concat(OrganizeImportsFeature.organizeImports(doc, context, unusedRanges));

		@:nullSafety(Off) // ?
		final diagnostics = existingActions.filter(action -> action.title == DiagnosticsFeature.RemoveUnusedImportUsingTitle)
			.map(action -> action.diagnostics)
			.flatten()
			.array();

		final actions:Array<CodeAction> = [];

		if (shouldOrganize) {
			actions.push({
				title: DiagnosticsFeature.OrganizeImportsUsingsTitle,
				kind: SourceOrganizeImports,
				edit: WorkspaceEditHelper.create(context, params, organizeFixes),
				diagnostics: diagnostics
			});
		}
		if (shouldSort) {
			actions.push({
				title: DiagnosticsFeature.SortImportsUsingsTitle,
				kind: CodeActionFeature.SourceSortImports,
				edit: WorkspaceEditHelper.create(context, params, sortFixes)
			});
		}

		if (shouldQuickFix && diagnostics.length > 0 && removeUnusedFixes.length > 1) {
			actions.push({
				title: DiagnosticsFeature.RemoveAllUnusedImportsUsingsTitle,
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, removeUnusedFixes),
				diagnostics: diagnostics
			});
		}

		return actions;
	}
}

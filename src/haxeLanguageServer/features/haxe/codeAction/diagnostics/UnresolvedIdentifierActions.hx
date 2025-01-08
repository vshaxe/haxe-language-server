package haxeLanguageServer.features.haxe.codeAction.diagnostics;

import haxeLanguageServer.Configuration;
import haxeLanguageServer.helper.ImportHelper;
import haxeLanguageServer.helper.TypeHelper;

class UnresolvedIdentifierActions {
	public static function createUnresolvedIdentifierActions(context:Context, params:CodeActionParams, diagnostic:Diagnostic):Array<CodeAction> {
		if ((params.context.only != null) && (!params.context.only.contains(QuickFix))) {
			return [];
		}
		final args = context.diagnostics.getArguments(params.textDocument.uri, DKUnresolvedIdentifier, diagnostic.range);
		if (args == null) {
			return [];
		}
		var actions:Array<CodeAction> = [];
		final importCount = args.count(a -> a.kind == UISImport);
		for (arg in args) {
			actions = actions.concat(switch arg.kind {
				case UISImport: createUnresolvedImportActions(context, params, diagnostic, arg, importCount);
				case UISTypo: createTypoActions(context, params, diagnostic, arg);
			});
		}
		return actions;
	}

	static function createUnresolvedImportActions(context:Context, params:CodeActionParams, diagnostic:Diagnostic, arg, importCount:Int):Array<CodeAction> {
		final doc = context.documents.getHaxe(params.textDocument.uri);
		if (doc == null || diagnostic.range == null) {
			return [];
		}
		final preferredStyle = context.config.user.codeGeneration.imports.style;
		final secondaryStyle:ImportStyle = if (preferredStyle == Type) Module else Type;

		final importPosition = determineImportPosition(doc);
		function makeImportAction(style:ImportStyle):CodeAction {
			final path = if (style == Module) TypeHelper.getModule(arg.name) else arg.name;
			return {
				title: "Import " + path,
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, [createImportsEdit(doc, importPosition, [arg.name], style)]),
				diagnostics: [diagnostic]
			};
		}

		final preferred = makeImportAction(preferredStyle);
		final secondary = makeImportAction(secondaryStyle);
		if (importCount == 1) {
			preferred.isPreferred = true;
		}
		final actions = [preferred, secondary];

		actions.push({
			title: "Change to " + arg.name,
			kind: QuickFix,
			edit: WorkspaceEditHelper.create(context, params, [
				{
					range: diagnostic.range.sure(),
					newText: arg.name
				}
			]),
			diagnostics: [diagnostic]
		});

		return actions;
	}

	static function createTypoActions(context:Context, params:CodeActionParams, diagnostic:Diagnostic, arg):Array<CodeAction> {
		if (diagnostic.range == null)
			return [];

		return [
			{
				title: "Change to " + arg.name,
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, [{range: diagnostic.range.sure(), newText: arg.name}]),
				diagnostics: [diagnostic]
			}
		];
	}
}

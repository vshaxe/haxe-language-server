package haxeLanguageServer.features.haxe.codeAction;

import haxe.display.Diagnostic.DiagnosticKind;
import haxeLanguageServer.features.haxe.DiagnosticsFeature;
import haxeLanguageServer.features.haxe.codeAction.CodeActionFeature;
import haxeLanguageServer.features.haxe.codeAction.diagnostics.AddTypeHintActions;
import haxeLanguageServer.features.haxe.codeAction.diagnostics.CompilerErrorActions;
import haxeLanguageServer.features.haxe.codeAction.diagnostics.FixAllAction;
import haxeLanguageServer.features.haxe.codeAction.diagnostics.MissingFieldsActions;
import haxeLanguageServer.features.haxe.codeAction.diagnostics.OrganizeImportActions;
import haxeLanguageServer.features.haxe.codeAction.diagnostics.ParserErrorActions;
import haxeLanguageServer.features.haxe.codeAction.diagnostics.ReplaceableCodeActions;
import haxeLanguageServer.features.haxe.codeAction.diagnostics.UnresolvedIdentifierActions;
import haxeLanguageServer.features.haxe.codeAction.diagnostics.UnusedImportActions;
import haxeLanguageServer.features.haxe.codeAction.diagnostics.UpdateSyntaxActions;
import languageServerProtocol.Types.CodeAction;

using Lambda;
using tokentree.TokenTreeAccessHelper;
using tokentree.utils.TokenTreeCheckUtils;

private enum FieldInsertionMode {
	IntoClass(rangeClass:Range, rangeEnd:Range);
}

class DiagnosticsCodeActionFeature implements CodeActionContributor {
	final context:Context;

	public function new(context) {
		this.context = context;
	}

	public function createCodeActions<T>(params:CodeActionParams) {
		if (!params.textDocument.uri.isFile()) {
			return [];
		}
		var actions:Array<CodeAction> = [];
		for (diagnostic in params.context.diagnostics) {
			final kind = diagnostic.data?.kind;
			if (kind == null || !(kind is Int)) { // our codes are int, so we don't handle other stuff
				continue;
			}
			final code:DiagnosticKind<T> = DiagnosticKindHelper.make(kind);
			actions = actions.concat(switch code {
				case DKUnusedImport: UnusedImportActions.createUnusedImportActions(context, params, diagnostic);
				case DKUnresolvedIdentifier: UnresolvedIdentifierActions.createUnresolvedIdentifierActions(context, params, diagnostic);
				case DKCompilerError: CompilerErrorActions.createCompilerErrorActions(context, params, diagnostic);
				case ReplacableCode: ReplaceableCodeActions.createReplaceableCodeActions(context, params, diagnostic);
				case DKParserError: ParserErrorActions.createParserErrorActions(context, params, diagnostic);
				case MissingFields: MissingFieldsActions.createMissingFieldsActions(context, params, diagnostic);
				case _: [];
			});
		}
		actions = OrganizeImportActions.createOrganizeImportActions(context, params, actions).concat(actions);
		actions = UpdateSyntaxActions.createUpdateSyntaxActions(context, params, actions).concat(actions);
		actions = AddTypeHintActions.createAddTypeHintActions(context, params, actions).concat(actions);
		actions = FixAllAction.createFixAllAction(context, params, actions).concat(actions);
		actions = actions.filterDuplicates((a, b) -> a.title == b.title);
		return actions;
	}
}

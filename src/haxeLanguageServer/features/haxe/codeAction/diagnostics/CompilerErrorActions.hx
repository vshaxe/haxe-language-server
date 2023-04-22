package haxeLanguageServer.features.haxe.codeAction.diagnostics;

import languageServerProtocol.Types.CodeActionKind;

class CompilerErrorActions {
	public static function createCompilerErrorActions(context:Context, params:CodeActionParams, diagnostic:Diagnostic):Array<CodeAction> {
		if ((params.context.only != null) && (!params.context.only.contains(QuickFix))) {
			return [];
		}
		final actions:Array<CodeAction> = [];
		final arg = context.diagnostics.getArguments(params.textDocument.uri, CompilerError, diagnostic.range);
		if (arg == null) {
			return actions;
		}
		final suggestionsRe = ~/\(Suggestions?: (.*)\)/;
		if (suggestionsRe.match(arg)) {
			final suggestions = suggestionsRe.matched(1).split(",");
			// Haxe reports the entire expression, not just the field position, so we have to be a bit creative here.
			final range = diagnostic.range;
			final fieldRe = ~/has no field ([^ ]+) /;
			if (fieldRe.match(arg)) {
				range.start.character = range.end.character - fieldRe.matched(1).length;
			}
			for (suggestion in suggestions) {
				suggestion = suggestion.trim();
				actions.push({
					title: "Change to " + suggestion,
					kind: QuickFix,
					edit: WorkspaceEditHelper.create(context, params, [{range: range, newText: suggestion}]),
					diagnostics: [diagnostic]
				});
			}
			return actions;
		}

		final invalidPackageRe = ~/Invalid package : ([\w.]*) should be ([\w.]*)/;
		if (invalidPackageRe.match(arg)) {
			final is = invalidPackageRe.matched(1);
			final shouldBe = invalidPackageRe.matched(2);
			final document = context.documents.getHaxe(params.textDocument.uri);
			if (document != null) {
				final replacement = document.getText(diagnostic.range).replace(is, shouldBe);
				actions.push({
					title: "Change to " + replacement,
					kind: CodeActionKind.QuickFix + ".auto",
					edit: WorkspaceEditHelper.create(context, params, [{range: diagnostic.range, newText: replacement}]),
					diagnostics: [diagnostic],
					isPreferred: true
				});
			}
		}

		if (context.haxeServer.haxeVersion.major >= 4 // unsuitable error range before Haxe 4
			&& arg.contains("should be declared with 'override' since it is inherited from superclass")) {
			var pos = diagnostic.range.start;
			final document = context.documents.getHaxe(params.textDocument.uri);
			if (document.tokens != null) {
				// Resolve parent token to add "override" before "fnunction" instead of function name
				final funPos = document.tokens!.getTokenAtOffset(document.offsetAt(diagnostic.range.start))!.parent!.pos!.min;
				if (funPos != null) {
					pos = document.positionAt(funPos);
				}
			}
			actions.push({
				title: "Add override keyword",
				kind: CodeActionKind.QuickFix + ".auto",
				edit: WorkspaceEditHelper.create(context, params, [{range: pos.toRange(), newText: "override "}]),
				diagnostics: [diagnostic],
				isPreferred: true
			});
		}

		final tooManyArgsRe = ~/Too many arguments([\w.]*)/;
		if (tooManyArgsRe.match(arg)) {
			final document = context.documents.getHaxe(params.textDocument.uri);
			final replacement = document.getText(diagnostic.range);
			final data:CodeActionResolveData = {
				type: MissingArg,
				params: params,
				diagnostic: diagnostic
			};
			actions.push({
				title: "Add argument",
				data: data,
				kind: RefactorRewrite,
				diagnostics: [diagnostic],
				isPreferred: false
			});
		}
		return actions;
	}
}

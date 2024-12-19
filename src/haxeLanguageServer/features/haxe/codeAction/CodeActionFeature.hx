package haxeLanguageServer.features.haxe.codeAction;

import haxeLanguageServer.features.haxe.codeAction.diagnostics.AddTypeHintActions;
import haxeLanguageServer.features.haxe.codeAction.diagnostics.ChangeFinalToVarAction;
import haxeLanguageServer.features.haxe.codeAction.diagnostics.MissingArgumentsAction;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.CodeAction;
import languageServerProtocol.Types.Diagnostic;

interface CodeActionContributor {
	function createCodeActions(params:CodeActionParams):Array<CodeAction>;
}

enum CodeActionResolveType {
	MissingArg;
	ChangeFinalToVar;
	AddTypeHint;
	ExtractInterface;
	ExtractMethod;
	ExtractType;
	ExtractConstructorParamsAsVars;
	ExtractConstructorParamsAsFinals;
	RewriteVarsToFinals;
	RewriteFinalsToVars;
	RewriteWrapWithTryCatch;
}

typedef CodeActionResolveData = {
	?type:CodeActionResolveType,
	params:CodeActionParams,
	?diagnostic:Diagnostic
}

class CodeActionFeature {
	public static inline final SourceSortImports = "source.sortImports";
	public static inline final SourceFixAll = "source.fixAll";

	final context:Context;
	final contributors:Array<CodeActionContributor> = [];
	final hasCommandResolveSupport:Bool;
	final refactorFeature:RefactorFeature;

	public function new(context) {
		this.context = context;
		refactorFeature = new RefactorFeature(context);

		context.registerCapability(CodeActionRequest.type, {
			documentSelector: Context.haxeSelector,
			codeActionKinds: [
				QuickFix,
				SourceOrganizeImports,
				SourceSortImports,
				RefactorExtract,
				RefactorRewrite,
				SourceFixAll
			],
			resolveProvider: true
		});
		hasCommandResolveSupport = context.capabilities.textDocument?.codeAction?.resolveSupport?.properties?.contains("command") ?? false;
		if (!hasCommandResolveSupport) {
			hasCommandResolveSupport = context.experimental?.forceCommandResolveSupport ?? false;
		}
		context.languageServerProtocol.onRequest(CodeActionRequest.type, onCodeAction);
		context.languageServerProtocol.onRequest(CodeActionResolveRequest.type, onCodeActionResolve);

		registerContributor(new ExtractVarFeature(context));
		registerContributor(new ExtractConstantFeature(context));
		registerContributor(new DiagnosticsCodeActionFeature(context));
		registerContributor(refactorFeature);
	}

	public function registerContributor(contributor:CodeActionContributor) {
		contributors.push(contributor);
	}

	function onCodeAction(params:CodeActionParams, token:CancellationToken, resolve:Array<CodeAction>->Void, reject:ResponseError<NoData>->Void) {
		var codeActions = [];
		for (contributor in contributors) {
			codeActions = codeActions.concat(contributor.createCodeActions(params));
		}
		resolve(codeActions);
	}

	function onCodeActionResolve(action:CodeAction, token:CancellationToken, resolve:CodeAction->Void, reject:ResponseError<NoData>->Void) {
		final data:Null<CodeActionResolveData> = action.data;
		final type = data?.type;
		final params = data?.params;
		final diagnostic = data?.diagnostic;
		if (type == null || params == null) {
			resolve(action);
			return;
		}
		switch (type) {
			case MissingArg, ChangeFinalToVar:
				// async actions from diagnostic errors
				if (diagnostic == null) {
					resolve(action);
					return;
				}
			case AddTypeHint:
			case ExtractInterface | ExtractMethod | ExtractType | ExtractConstructorParamsAsVars | ExtractConstructorParamsAsFinals | RewriteVarsToFinals |
				RewriteFinalsToVars | RewriteWrapWithTryCatch:
		}
		switch (type) {
			case MissingArg, ChangeFinalToVar, AddTypeHint:
				final promise = switch type {
					case MissingArg:
						MissingArgumentsAction.createMissingArgumentsAction(context, action, params, diagnostic);
					case ChangeFinalToVar:
						ChangeFinalToVarAction.createChangeFinalToVarAction(context, action, params, diagnostic);
					case AddTypeHint:
						AddTypeHintActions.createAddTypeHintAction(context, action, params);
					case _: null;
				}
				if (promise == null) {
					reject(ResponseError.internalError("failed to resolve missing arguments action"));
					return;
				}
				promise.then(action -> {
					resolve(action);
					final command = action.command;
					if (command == null || hasCommandResolveSupport)
						return;
					context.languageServerProtocol.sendNotification(LanguageServerMethods.ExecuteClientCommand, {
						command: command.command,
						arguments: command.arguments ?? []
					});
				}).catchError((e) -> reject(e));
			case ExtractInterface | ExtractMethod | ExtractType | ExtractConstructorParamsAsVars | ExtractConstructorParamsAsFinals | RewriteVarsToFinals |
				RewriteFinalsToVars | RewriteWrapWithTryCatch:
				refactorFeature.createCodeActionEdits(context, type, action, params).then(workspaceEdit -> {
					action.edit = workspaceEdit;
					resolve(action);
				}).catchError((e) -> reject(e));
		}
	}
}

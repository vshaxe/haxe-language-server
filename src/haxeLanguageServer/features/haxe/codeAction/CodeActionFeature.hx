package haxeLanguageServer.features.haxe.codeAction;

import js.lib.Promise;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.CodeAction;

interface CodeActionContributor {
	function createCodeActions(params:CodeActionParams):Array<CodeAction>;
}

enum CodeActionResolveEnum {
	MissingArg(callback:(action:CodeAction) -> Null<Promise<CodeAction>>);
}

typedef CodeActionResolveData = {
	?enumId:Int
}

class CodeActionFeature {
	public static inline final SourceSortImports = "source.sortImports";
	static final resolveCallbacks:Array<Null<CodeActionResolveEnum>> = [];

	final context:Context;
	final contributors:Array<CodeActionContributor> = [];

	public function new(context, diagnostics) {
		this.context = context;

		context.registerCapability(CodeActionRequest.type, {
			documentSelector: Context.haxeSelector,
			codeActionKinds: [QuickFix, SourceOrganizeImports, SourceSortImports, RefactorExtract],
			resolveProvider: true,
		});
		context.languageServerProtocol.onRequest(CodeActionRequest.type, onCodeAction);
		context.languageServerProtocol.onRequest(CodeActionResolveRequest.type, onCodeActionResolve);

		registerContributor(new ExtractConstantFeature(context));
		registerContributor(new DiagnosticsCodeActionFeature(context, diagnostics));
		#if debug
		registerContributor(new ExtractTypeFeature(context));
		registerContributor(new ExtractFunctionFeature(context));
		#end
	}

	public function registerContributor(contributor:CodeActionContributor) {
		contributors.push(contributor);
	}

	function onCodeAction(params:CodeActionParams, token:CancellationToken, resolve:Array<CodeAction>->Void, reject:ResponseError<NoData>->Void) {
		resolveCallbacks.resize(0);
		var codeActions = [];
		for (contributor in contributors) {
			codeActions = codeActions.concat(contributor.createCodeActions(params));
		}
		resolve(codeActions);
	}

	function onCodeActionResolve(action:CodeAction, token:CancellationToken, resolve:CodeAction->Void, reject:ResponseError<NoData>->Void) {
		final data:Null<CodeActionResolveData> = action.data;
		final enumId = data!.enumId;
		if (enumId != null) {
			final data = resolveCallbacks[enumId];
			if (data == null)
				throw 'resolveCallbacks[$enumId] is null';
			switch data {
				case MissingArg(callback):
					final promise = callback(action);
					promise!.then(action -> {
						resolve(action);
						final command = action.command;
						if (command == null)
							return;
						context.languageServerProtocol.sendNotification(LanguageServerMethods.ExecuteClientCommand, {
							command: command.command,
							arguments: command.arguments ?? []
						});
					});
			}
			return;
		}

		resolve(action);
	}

	public static function addResolveData(data:CodeActionResolveEnum):Int {
		var i = resolveCallbacks.indexOf(null);
		if (i == -1)
			i = resolveCallbacks.length;
		resolveCallbacks[i] = data;
		return i;
	}
}

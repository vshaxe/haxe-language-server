package haxeLanguageServer.features.haxe.codeAction;

import js.lib.Promise;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.CodeAction;

interface CodeActionContributor {
	function createCodeActions(params:CodeActionParams):Array<CodeAction>;
}

enum CodeActionResolveData {
	MissingArg(callback:(action:CodeAction) -> Null<Promise<CodeAction>>);
}

class CodeActionFeature {
	public static inline final SourceSortImports = "source.sortImports";
	static final resolveCallbacks:Array<Null<CodeActionResolveData>> = [];

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
		final index = action.data;
		if (index == null || !(index is Int)) {
			throw "action.data should be Int index of resolve callback";
		}
		final data = resolveCallbacks[index];
		if (data == null)
			throw 'resolveCallbacks[$index] is null';
		switch data {
			case MissingArg(callback):
				final promise = callback(action);
				promise!.then(action -> {
					resolve(action);
				});
		}
	}

	public static function addResolveData(data:CodeActionResolveData):Int {
		var i = resolveCallbacks.indexOf(null);
		if (i == -1)
			i = resolveCallbacks.length;
		resolveCallbacks[i] = data;
		return i;
	}
}

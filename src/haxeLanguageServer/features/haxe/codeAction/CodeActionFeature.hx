package haxeLanguageServer.features.haxe.codeAction;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.CodeAction;

interface CodeActionContributor {
	function createCodeActions(params:CodeActionParams):Array<CodeAction>;
}

class CodeActionFeature {
	public static inline final SourceSortImports = "source.sortImports";

	final context:Context;
	final contributors:Array<CodeActionContributor> = [];

	public function new(context, diagnostics) {
		this.context = context;

		context.registerCapability(CodeActionRequest.type, {
			documentSelector: Context.haxeSelector,
			codeActionKinds: [QuickFix, SourceOrganizeImports, SourceSortImports, RefactorExtract]
		});
		context.languageServerProtocol.onRequest(CodeActionRequest.type, onCodeAction);

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
		var codeActions = [];
		for (contributor in contributors) {
			codeActions = codeActions.concat(contributor.createCodeActions(params));
		}
		resolve(codeActions);
	}
}

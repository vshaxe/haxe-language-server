package haxeLanguageServer.features.haxe;

import haxeLanguageServer.features.haxe.codeAction.CodeActionFeature.CodeActionContributor;
import haxeLanguageServer.features.haxe.codeAction.CodeActionFeature.CodeActionResolveType;
import haxeLanguageServer.features.haxe.refactoring.EditList;
import haxeLanguageServer.features.haxe.refactoring.RefactorCache;
import js.lib.Promise;
import jsonrpc.ResponseError;
import languageServerProtocol.Types.CodeAction;
import languageServerProtocol.Types.CodeActionKind;
import languageServerProtocol.Types.WorkspaceEdit;
import refactor.RefactorResult;
import refactor.Refactoring;
import refactor.refactor.RefactorHelper;
import refactor.refactor.RefactorType;
import refactor.refactor.RewriteWrapWithTryCatch;

class RefactorFeature implements CodeActionContributor {
	final context:Context;
	final refactorCache:RefactorCache;

	public function new(context:Context) {
		this.context = context;
		this.refactorCache = context.refactorCache;
	}

	public function createCodeActions(params:CodeActionParams):Array<CodeAction> {
		if (context.config.user.disableRefactorCache) {
			return [];
		}

		var actions:Array<CodeAction> = [];
		if (params.context.only != null) {
			actions = actions.concat(findMatchingRefactors(params, i -> {
				if (i == null) {
					return false;
				}
				return params.context.only.contains(i.codeActionKind);
			}));
		} else {
			actions = actions.concat(findMatchingRefactors(params, i -> true));
		}

		return actions;
	}

	function findMatchingRefactors(params:CodeActionParams, filterType:FilterRefactorModuleCB):Array<CodeAction> {
		var actions:Array<CodeAction> = [];
		final canRefactorContext = refactorCache.makeCanRefactorContext(context.documents.getHaxe(params.textDocument.uri), params.range);
		if (canRefactorContext == null) {
			return actions;
		}
		var allRefactorInfos:Array<Null<RefactorInfo>> = [
			getRefactorInfo(ExtractConstructorParamsAsFinals),
			getRefactorInfo(ExtractConstructorParamsAsVars),
			getRefactorInfo(ExtractInterface),
			getRefactorInfo(ExtractMethod),
			getRefactorInfo(ExtractType),
			getRefactorInfo(RewriteFinalsToVars),
			getRefactorInfo(RewriteVarsToFinals),
			getRefactorInfo(RewriteWrapWithTryCatch),
		];
		final refactorInfo = allRefactorInfos.filter(filterType);
		if (refactorInfo.length <= 0) {
			return actions;
		}
		final isRangeSameScope = RefactorHelper.rangeInSameScope(canRefactorContext);
		refactorCache.updateSingleFileCache(canRefactorContext.what.fileName);
		for (refactor in refactorInfo) {
			if (refactor == null) {
				continue;
			}
			switch (Refactoring.canRefactor(refactor.refactorType, canRefactorContext, isRangeSameScope)) {
				case Unsupported:
				case Supported(title):
					actions.push(makeEmptyCodeAction(title, refactor.codeActionKind, params, refactor.type));
			}
		}
		return actions;
	}

	function getRefactorInfo(type:CodeActionResolveType):Null<RefactorInfo> {
		switch (type) {
			case MissingArg | ChangeFinalToVar | AddTypeHint:
				return null;
			case ExtractInterface:
				return {
					refactorType: RefactorExtractInterface,
					type: type,
					codeActionKind: RefactorExtract,
					title: "extractInterface",
					prefix: "[ExtractInterface]"
				}
			case ExtractMethod:
				return {
					refactorType: RefactorExtractMethod,
					type: type,
					codeActionKind: RefactorExtract,
					title: "extractMethod",
					prefix: "[ExtractMethod]"
				}
			case ExtractType:
				return {
					refactorType: RefactorExtractType,
					type: type,
					codeActionKind: RefactorExtract,
					title: "extractType",
					prefix: "[ExtractType]"
				}
			case ExtractConstructorParamsAsVars:
				return {
					refactorType: RefactorExtractConstructorParams(false),
					type: type,
					codeActionKind: RefactorExtract,
					title: "extractConstructorParamsAsVars",
					prefix: "[ExtractConstructorParams as Vars]"
				}
			case ExtractConstructorParamsAsFinals:
				return {
					refactorType: RefactorExtractConstructorParams(true),
					type: type,
					codeActionKind: RefactorExtract,
					title: "extractConstructorParamsAsFinals",
					prefix: "[ExtractConstructorParams as Finals]"
				}
			case RewriteVarsToFinals:
				return {
					refactorType: RefactorRewriteVarsToFinals(true),
					type: type,
					codeActionKind: RefactorRewrite,
					title: "rewriteVarsToFinals",
					prefix: "[RefactorRewriteVarsToFinals]"
				}
			case RewriteFinalsToVars:
				return {
					refactorType: RefactorRewriteVarsToFinals(false),
					type: type,
					codeActionKind: RefactorRewrite,
					title: "rewriteFinalsToVars",
					prefix: "[RewriteFinalsToVars]"
				}
			case RewriteWrapWithTryCatch:
				return {
					refactorType: RefactorRewriteWrapWithTryCatch,
					type: type,
					codeActionKind: RefactorRewrite,
					title: "rewriteWrapInException",
					prefix: "[RewriteWrapInException]"
				}
		}
	}

	function makeEmptyCodeAction(title:String, kind:CodeActionKind, params:CodeActionParams, type:CodeActionResolveType):CodeAction {
		return {
			title: title,
			kind: kind,
			data: {params: params, type: type}
		}
	}

	public function createCodeActionEdits(context:Context, type:CodeActionResolveType, action:CodeAction, params:CodeActionParams):Promise<WorkspaceEdit> {
		var endProgress = context.startProgress("Performing Refactor Operation…");
		var actions:Array<CodeAction> = [];
		final editList:EditList = new EditList();
		final refactorContext = refactorCache.makeRefactorContext(context.documents.getHaxe(params.textDocument.uri), params.range, editList);
		if (refactorContext == null) {
			return Promise.reject("failed to make refactor context");
		}
		var info = getRefactorInfo(type);
		if (info == null) {
			return Promise.reject("failed to make refactor context");
		}
		final onResolve:(?result:Null<Dynamic>, ?debugInfo:Null<String>) -> Void = context.startTimer("refactor/" + info.title);
		return Refactoring.doRefactor(info.refactorType, refactorContext).then((result:RefactorResult) -> {
			var promise = switch (result) {
				case NoChange:
					trace(info.prefix + " no change");
					Promise.reject(ResponseError.internalError("no change"));
				case NotFound:
					var msg = 'could not find identifier at "${refactorContext.what.fileName}@${refactorContext.what.posStart}-${refactorContext.what.posEnd}"';
					trace('${info.prefix} $msg');
					Promise.reject(ResponseError.internalError(msg));
				case Unsupported(name):
					trace('${info.prefix} refactoring not supported for "$name"');
					Promise.reject(ResponseError.internalError('refactoring not supported for "$name"'));
				case DryRun:
					trace(info.prefix + " dry run");
					Promise.reject(ResponseError.internalError("dry run"));
				case Done:
					var edit:WorkspaceEdit = {documentChanges: editList.documentChanges};
					Promise.resolve(edit);
			}
			endProgress();
			onResolve(null, editList.documentChanges.length + " changes");
			return promise;
		}).catchError((msg) -> {
			trace('${info.prefix} error: $msg');
			endProgress();
			onResolve(null, "error");
			Promise.reject(ResponseError.internalError('$msg'));
		});
	}
}

typedef RefactorInfo = {
	var refactorType:RefactorType;
	var type:CodeActionResolveType;
	var codeActionKind:CodeActionKind;
	var title:String;
	var prefix:String;
}

typedef FilterRefactorModuleCB = (info:Null<RefactorInfo>) -> Bool;

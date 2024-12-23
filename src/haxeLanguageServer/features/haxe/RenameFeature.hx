package haxeLanguageServer.features.haxe;

import byte.ByteData;
import haxe.PosInfos;
import haxe.io.Path;
import haxeLanguageServer.features.haxe.refactoring.EditDoc;
import haxeLanguageServer.features.haxe.refactoring.EditList;
import haxeLanguageServer.features.haxe.refactoring.LanguageServerTyper;
import haxeLanguageServer.features.haxe.refactoring.RefactorCache;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.WorkspaceEdit;
import refactor.RefactorResult;
import refactor.discover.FileContentType;
import refactor.discover.TraverseSources.simpleFileReader;
import refactor.rename.CanRenameResult;
import tokentree.TokenTree;

using Lambda;
using haxeLanguageServer.helper.PathHelper;

class RenameFeature {
	final context:Context;
	final refactorCache:RefactorCache;

	static final HINT_SETTINGS = " - check `haxe.renameSourceFolders` setting (see https://github.com/vshaxe/vshaxe/wiki/Rename-Symbol)";

	public function new(context:Context, refactorCache:RefactorCache) {
		this.context = context;
		this.refactorCache = refactorCache;

		context.languageServerProtocol.onRequest(PrepareRenameRequest.type, onPrepareRename);
		context.languageServerProtocol.onRequest(RenameRequest.type, onRename);
	}

	function onPrepareRename(params:PrepareRenameParams, token:CancellationToken, resolve:PrepareRenameResult->Void, reject:ResponseError<NoData>->Void) {
		if (context.config.user.disableRefactorCache) {
			return reject.handler()("rename feature disabled");
		}

		final onResolve:(?result:Null<Dynamic>, ?debugInfo:Null<String>) -> Void = context.startTimer("textDocument/prepareRename");
		final uri = params.textDocument.uri;
		final doc:Null<HaxeDocument> = context.documents.getHaxe(uri);
		if (doc == null || !uri.isFile()) {
			return reject.noFittingDocument(uri);
		}

		final filePath:FsPath = uri.toFsPath();

		final usageContext:refactor.discover.UsageContext = refactorCache.makeUsageContext();
		usageContext.fileName = filePath.toString();

		refactorCache.updateSingleFileCache(filePath.toString());

		final editList:EditList = new EditList();
		refactor.Rename.canRename(refactorCache.makeCanRenameContext(doc, filePath, params.position)).then((result:CanRenameResult) -> {
			if (result == null) {
				reject(ResponseError.internalError("cannot rename identifier"));
			}
			var editDoc = new EditDoc(filePath, editList, context, refactorCache.converter);
			resolve({
				range: editDoc.posToRange(result.pos),
				placeholder: result.name
			});
			onResolve();
		}).catchError((msg) -> {
			trace('[canRename] error: $msg');
			reject(ResponseError.internalError('$msg'));
		});
	}

	function onRename(params:RenameParams, token:CancellationToken, resolve:WorkspaceEdit->Void, reject:ResponseError<NoData>->Void) {
		final onResolve:(?result:Null<Dynamic>, ?debugInfo:Null<String>) -> Void = context.startTimer("textDocument/rename");
		final uri = params.textDocument.uri;
		final doc:Null<HaxeDocument> = context.documents.getHaxe(uri);
		if (doc == null || !uri.isFile()) {
			return reject.noFittingDocument(uri);
		}

		var endProgress = context.startProgress("Performing Rename Operation…");

		final filePath:FsPath = uri.toFsPath();

		final editList:EditList = new EditList();
		refactor.Rename.rename(refactorCache.makeRenameContext(doc, filePath, params.position, params.newName, editList)).then((result:RefactorResult) -> {
			endProgress();
			switch (result) {
				case NoChange:
					trace("[rename] no change");
					reject(ResponseError.internalError("no change"));
				case NotFound:
					trace('[rename] could not find identifier at "$filePath@${params.position}"$HINT_SETTINGS');
					reject(ResponseError.internalError('could not find identifier at "$filePath@${params.position}"$HINT_SETTINGS'));
				case Unsupported(name):
					trace('[rename] refactoring not supported for "$name"');
					reject(ResponseError.internalError('refactoring not supported for "$name"'));
				case DryRun:
					trace("[rename] dry run");
					reject(ResponseError.internalError("dry run"));
				case Done:
					resolve({documentChanges: editList.documentChanges});
			}
			onResolve(null, editList.documentChanges.length + " changes");
		}).catchError((msg) -> {
			endProgress();
			trace('[rename] error: $msg$HINT_SETTINGS');
			onResolve(null, "error");
			reject(ResponseError.internalError('$msg$HINT_SETTINGS'));
		});
	}
}

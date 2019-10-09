package haxeLanguageServer.features;

import haxe.io.Path;
import sys.FileSystem;
import haxeLanguageServer.helper.WorkspaceEditHelper;
import tokentree.TokenTree;
import tokentree.utils.TokenTreeCheckUtils;

using tokentree.TokenTreeAccessHelper;

class ExtractTypeFeature {
	final context:Context;

	public function new(context:Context) {
		this.context = context;
		#if debug
		context.registerCodeActionContributor(extractType);
		#end
	}

	function extractType(params:CodeActionParams):Array<CodeAction> {
		var doc = context.documents.get(params.textDocument.uri);
		try {
			var fsPath:FsPath = params.textDocument.uri.toFsPath();
			var path:Path = new Path(fsPath.toString());
			if (path.ext != "hx")
				return [];

			if ((doc.tokens == null) || (doc.tokens.tree == null))
				return [];

			var types:Array<TokenTree> = doc.tokens.tree.filterCallback(function(token:TokenTree, index:Int):FilterResult {
				switch (token.tok) {
					case Kwd(KwdClass), Kwd(KwdInterface), Kwd(KwdEnum), Kwd(KwdAbstract), Kwd(KwdTypedef):
						return FOUND_SKIP_SUBTREE;
					default:
				}
				return GO_DEEPER;
			});
			var lastImport:Null<TokenTree> = getLastImportToken(doc);
			if (isInsideConditional(lastImport))
				return [];

			var fileHeader = "";

			// copy all imports from current file
			// TODO reduce imports
			if (lastImport != null) {
				var pos = lastImport.getPos();
				pos.min = 0;

				var range = rangeAt(doc, pos);
				range.end.line++;
				range.end.character = 0;
				fileHeader = doc.getText(range) + "\n";
			}

			var actions = [];
			for (type in types) {
				if (isInsideConditional(type)) {
					// TODO support types inside conditionals
					continue;
				}
				var nameTok:TokenTree = type.access().firstChild().isCIdent().token;
				if (nameTok == null)
					continue;

				var name:String = nameTok.toString();
				if (name == path.file)
					continue;

				var newFileName:String = Path.join([path.dir, name + ".hx"]);
				if (FileSystem.exists(newFileName))
					continue;

				var pos = type.getPos();
				var docComment:Null<TokenTree> = TokenTreeCheckUtils.getDocComment(type);
				if (docComment != null) {
					// expand pos.min to capture doc comment
					pos.min = docComment.pos.min;
				}
				var typeRange = rangeAt(doc, pos);

				// remove code from current file
				var removeOld:TextDocumentEdit = WorkspaceEditHelper.textDocumentEdit(params.textDocument.uri, [WorkspaceEditHelper.removeText(typeRange)]);

				// create new file
				var newUri:DocumentUri = FsPathHelper.toUri(new FsPath(newFileName));
				var createFile:CreateFile = WorkspaceEditHelper.createNewFile(newUri, false, true);

				// copy file header, type and doc comment into new file
				var addNewType:TextDocumentEdit = WorkspaceEditHelper.textDocumentEdit(newUri, [
					WorkspaceEditHelper.insertText(doc.positionAt(0), fileHeader + doc.getText(typeRange))
				]);

				// TODO edits in files that use type

				var edit:WorkspaceEdit = {
					documentChanges: [removeOld, createFile, addNewType]
				};

				actions.push({
					title: 'Extract $name to a new file',
					kind: RefactorExtract,
					edit: edit
				});
			}
			return actions;
		} catch (e:Any) {}
		return [];
	}

	function getLastImportToken(doc:TextDocument):Null<TokenTree> {
		var imports:Array<TokenTree> = doc.tokens.tree.filterCallback(function(token:TokenTree, index:Int):FilterResult {
			switch (token.tok) {
				case Kwd(KwdImport), Kwd(KwdUsing):
					return FOUND_SKIP_SUBTREE;
				default:
			}
			return GO_DEEPER;
		});
		return imports.pop();
	}

	function isInsideConditional(token:TokenTree):Bool {
		if (token == null)
			return false;

		var parent:Null<TokenTree> = token.parent;
		while ((parent != null) && (parent.tok != null)) {
			switch (parent.tok) {
				case Sharp(_):
					return true;
				default:
			}
			parent = parent.parent;
		}
		return false;
	}

	inline function rangeAt(document:TextDocument, pos:haxe.macro.Expr.Position):Range {
		return document.rangeAt(pos.min, pos.max);
	}
}

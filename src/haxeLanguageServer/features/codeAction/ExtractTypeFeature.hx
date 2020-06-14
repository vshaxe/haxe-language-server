package haxeLanguageServer.features.codeAction;

import haxe.io.Path;
import haxeLanguageServer.helper.WorkspaceEditHelper;
import sys.FileSystem;
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
		var doc = context.documents.getHaxe(params.textDocument.uri);
		if (doc == null || doc.tokens == null || doc.tokens.tree == null) {
			return [];
		}
		try {
			var fsPath:FsPath = params.textDocument.uri.toFsPath();
			var path = new Path(fsPath.toString());

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

			// copy all imports from current file
			// TODO reduce imports
			var fileHeader = copyImports(doc, path.file, lastImport);

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

				var pos = doc.tokens.getTreePos(type);
				var docComment:Null<TokenTree> = TokenTreeCheckUtils.getDocComment(type);
				if (docComment != null) {
					// expand pos.min to capture doc comment
					pos.min = doc.tokens.getPos(docComment).min;
				}
				var typeRange = doc.rangeAt2(pos);
				if (params.range.intersection(typeRange) == null) {
					// no overlap between selection / cursor pos and Haxe type
					continue;
				}

				// remove code from current file
				var removeOld:TextDocumentEdit = WorkspaceEditHelper.textDocumentEdit(params.textDocument.uri, [WorkspaceEditHelper.removeText(typeRange)]);

				// create new file
				var newUri:DocumentUri = new FsPath(newFileName).toUri();
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
		} catch (e) {
			return [];
		}
	}

	function copyImports(doc:HaxeDocument, fileName:String, lastImport:Null<TokenTree>):String {
		if (lastImport == null)
			return "";

		var pos = doc.tokens.getTreePos(lastImport);
		pos.min = 0;

		var range = doc.rangeAt2(pos);
		range.end.line++;
		range.end.character = 0;
		var fileHeader:String = doc.getText(range);

		var pack:Null<TokenTree>;
		doc.tokens.tree.filterCallback(function(token:TokenTree, index:Int):FilterResult {
			switch (token.tok) {
				case Kwd(KwdPackage):
					pack = token;
					return SKIP_SUBTREE;
				default:
					return SKIP_SUBTREE;
			}
		});
		if (pack == null)
			return fileHeader + "\n";

		var packText:String = doc.getText(doc.rangeAt2(doc.tokens.getTreePos(pack)));
		packText = packText.replace("package ", "");
		packText = packText.replace(";", "").trim();
		if (packText.length <= 0)
			packText = '${fileName}';
		else
			packText += '.${fileName}';

		return fileHeader + 'import $packText;\n\n';
	}

	function getLastImportToken(doc:HaxeDocument):Null<TokenTree> {
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
}

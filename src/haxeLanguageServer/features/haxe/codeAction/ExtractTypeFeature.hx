package haxeLanguageServer.features.haxe.codeAction;

import haxe.io.Path;
import haxeLanguageServer.helper.WorkspaceEditHelper;
import haxeLanguageServer.tokentree.TokenTreeManager;
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
		final uri = params.textDocument.uri;
		final doc = context.documents.getHaxe(uri);
		if (doc == null) {
			return [];
		}
		final tokens = doc.tokens;
		if (tokens == null) {
			return [];
		}
		return try {
			final fsPath:FsPath = uri.toFsPath();
			final path = new Path(fsPath.toString());

			final types:Array<TokenTree> = tokens.tree.filterCallback(function(token:TokenTree, index:Int):FilterResult {
				switch (token.tok) {
					case Kwd(KwdClass), Kwd(KwdInterface), Kwd(KwdEnum), Kwd(KwdAbstract), Kwd(KwdTypedef):
						return FOUND_SKIP_SUBTREE;
					default:
				}
				return GO_DEEPER;
			});
			final lastImport:Null<TokenTree> = getLastImportToken(tokens.tree);
			if (isInsideConditional(lastImport))
				return [];

			// copy all imports from current file
			// TODO reduce imports
			final fileHeader = copyImports(doc, tokens, path.file, lastImport);

			final actions = [];
			for (type in types) {
				if (isInsideConditional(type)) {
					// TODO support types inside conditionals
					continue;
				}
				final nameTok:Null<TokenTree> = type.access().firstChild().isCIdent().token;
				if (nameTok == null)
					continue;

				final name:String = nameTok.toString();
				if (name == path.file || path.dir == null)
					continue;

				final newFileName:String = Path.join([path.dir, name + ".hx"]);
				if (FileSystem.exists(newFileName))
					continue;

				final pos = tokens.getTreePos(type);
				final docComment:Null<TokenTree> = TokenTreeCheckUtils.getDocComment(type);
				if (docComment != null) {
					// expand pos.min to capture doc comment
					pos.min = tokens.getPos(docComment).min;
				}
				final typeRange = doc.rangeAt2(pos);
				if (params.range.intersection(typeRange) == null) {
					// no overlap between selection / cursor pos and Haxe type
					continue;
				}

				// remove code from current file
				final removeOld:TextDocumentEdit = WorkspaceEditHelper.textDocumentEdit(uri, [WorkspaceEditHelper.removeText(typeRange)]);

				// create new file
				final newUri:DocumentUri = new FsPath(newFileName).toUri();
				final createFile:CreateFile = WorkspaceEditHelper.createNewFile(newUri, false, true);

				// copy file header, type and doc comment into new file
				final addNewType:TextDocumentEdit = WorkspaceEditHelper.textDocumentEdit(newUri, [
					WorkspaceEditHelper.insertText(doc.positionAt(0), fileHeader + doc.getText(typeRange))
				]);

				// TODO edits in files that use type

				final edit:WorkspaceEdit = {
					documentChanges: [removeOld, createFile, addNewType]
				};

				actions.push({
					title: 'Extract $name to a new file',
					kind: RefactorExtract,
					edit: edit
				});
			}
			actions;
		} catch (e) {
			[];
		}
	}

	function copyImports(doc:HaxeDocument, tokens:TokenTreeManager, fileName:String, lastImport:Null<TokenTree>):String {
		if (lastImport == null)
			return "";

		final pos = tokens.getTreePos(lastImport);
		pos.min = 0;

		final range = doc.rangeAt2(pos);
		range.end.line++;
		range.end.character = 0;
		final fileHeader:String = doc.getText(range);

		var pack:Null<TokenTree>;
		tokens.tree.filterCallback(function(token:TokenTree, index:Int):FilterResult {
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

		var packText:String = doc.getText(doc.rangeAt2(tokens.getTreePos(pack)));
		packText = packText.replace("package ", "");
		packText = packText.replace(";", "").trim();
		if (packText.length <= 0)
			packText = '${fileName}';
		else
			packText += '.${fileName}';

		return fileHeader + 'import $packText;\n\n';
	}

	function getLastImportToken(tree:TokenTree):Null<TokenTree> {
		final imports:Array<TokenTree> = tree.filterCallback(function(token:TokenTree, index:Int):FilterResult {
			switch (token.tok) {
				case Kwd(KwdImport), Kwd(KwdUsing):
					return FOUND_SKIP_SUBTREE;
				default:
			}
			return GO_DEEPER;
		});
		return imports.pop();
	}

	function isInsideConditional(token:Null<TokenTree>):Bool {
		if (token == null)
			return false;

		var parent:Null<TokenTree> = token.parent;
		while (parent != null && parent.tok != null) {
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

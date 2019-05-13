package haxeLanguageServer.helper;

import haxe.Json;
import haxe.display.JsonModuleTypes;
import haxeLanguageServer.protocol.helper.DisplayPrinter;
import haxeLanguageServer.TextDocument;
import haxeLanguageServer.Configuration.ImportStyle;
import haxeLanguageServer.Configuration.FunctionFormattingConfig;

using tokentree.TokenTreeAccessHelper;
using Lambda;

typedef ImportPosition = {
	final position:Position;
	final insertLineBefore:Bool;
	final insertLineAfter:Bool;
}

class ImportHelper {
	public static function createImportsEdit(doc:TextDocument, result:ImportPosition, paths:Array<String>, style:ImportStyle):TextEdit {
		if (style == Module) {
			paths = paths.map(TypeHelper.getModule);
		}
		var importData = {
			range: result.position.toRange(),
			newText: paths.map(path -> 'import $path;\n').join("")
		};
		if (result.insertLineBefore && doc.lineAt(result.position.line - 1).trim().length > 0) {
			importData.newText = "\n" + importData.newText;
		}
		if (result.insertLineAfter) {
			importData.newText += "\n";
		}
		return importData;
	}

	public static function createFunctionImportsEdit<T>(doc:TextDocument, result:ImportPosition, context:Context, type:JsonType<T>,
			formatting:FunctionFormattingConfig):Array<TextEdit> {
		var importConfig = context.config.user.codeGeneration.imports;
		if (!importConfig.enableAutoImports) {
			return [];
		}
		var paths = [];
		var signature = type.extractFunctionSignature();
		if (formatting.argumentTypeHints && (!formatting.useArrowSyntax || signature.args.length != 1)) {
			paths = paths.concat(signature.args.map(arg -> arg.t.resolveImports()).flatten().array());
		}
		if (formatting.printReturn(signature)) {
			paths = paths.concat(signature.ret.resolveImports());
		}
		paths = paths.filterDuplicates((e1, e2) -> Json.stringify(e1) == Json.stringify(e2));

		if (paths.length == 0) {
			return [];
		} else {
			var printer = new DisplayPrinter(false, Always);
			return [createImportsEdit(doc, result, paths.map(printer.printPath), importConfig.style)];
		}
	}

	public static function getImportPosition(document:TextDocument):ImportPosition {
		var tokens = document.tokens;
		if (tokens == null) {
			return null;
		}
		var firstImport = null;
		var firstType = null;

		tokens.tree.filterCallback((tree, _) -> {
			switch tree.tok {
				case Kwd(KwdPackage):
				// ignore
				case Kwd(KwdImport | KwdUsing) | Sharp("if") if (firstImport == null):
					firstImport = tree;
				case Kwd(_) if (firstType == null):
					firstType = tree;
				case _:
			}
			return SKIP_SUBTREE;
		});

		return if (firstImport != null) {
			{
				position: document.positionAt(tokens.getPos(firstImport).min),
				insertLineBefore: false,
				insertLineAfter: false
			}
		} else if (firstType != null) {
			var token = firstType;
			var previousSibling = null;
			var docCommentSkipped = false;
			do {
				previousSibling = token.access().previousSibling();
				if (!previousSibling.exists()) {
					break;
				}
				switch previousSibling.token.tok {
					case CommentLine(_):
						token = previousSibling.token;
					case Comment(_) if (!docCommentSkipped):
						token = previousSibling.token;
						docCommentSkipped = true;
					case _:
						break;
				}
			} while (true);
			{
				position: document.positionAt(tokens.getPos(token).min),
				insertLineBefore: token.access().previousSibling().exists(),
				insertLineAfter: true
			}
		} else {
			{
				position: {line: 0, character: 0},
				insertLineAfter: false,
				insertLineBefore: false
			}
		}
	}
}

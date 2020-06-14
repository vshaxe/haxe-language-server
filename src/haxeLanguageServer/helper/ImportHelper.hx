package haxeLanguageServer.helper;

import haxe.Json;
import haxe.display.JsonModuleTypes;
import haxeLanguageServer.Configuration.FunctionFormattingConfig;
import haxeLanguageServer.Configuration.ImportStyle;
import haxeLanguageServer.protocol.DisplayPrinter;

using Lambda;
using tokentree.TokenTreeAccessHelper;

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
		function isLineEmpty(delta:Int) {
			return doc.lineAt(result.position.line + delta).trim().length == 0;
		}
		if (result.insertLineBefore && !isLineEmpty(-1)) {
			importData.newText = "\n" + importData.newText;
		}
		if (result.insertLineAfter && !isLineEmpty(0)) {
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
		var packageStatement = null;

		// if the first token in the file is a comment, we should add the import after this
		var firstComment = if (tokens.list[0].tok.match(Comment(_))) {
			tokens.list[0];
		} else {
			null;
		}

		tokens.tree.filterCallback((tree, _) -> {
			switch tree.tok {
				case Kwd(KwdPackage):
					packageStatement = tree;
				case Kwd(KwdImport | KwdUsing) | Sharp("if") if (firstImport == null):
					firstImport = tree;
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
		} else if (packageStatement != null) {
			var lastChild = packageStatement.getLastChild();
			var pos = document.positionAt(tokens.getPos(lastChild != null ? lastChild : packageStatement).max);
			pos.line += 1;
			pos.character = 0;
			{
				position: pos,
				insertLineAfter: true,
				insertLineBefore: true
			}
		} else if (firstComment != null) {
			var pos = document.positionAt(firstComment.pos.max);
			pos.line += 1;
			pos.character = 0;
			{
				position: pos,
				insertLineAfter: true,
				insertLineBefore: true
			}
		} else {
			{
				position: {line: 0, character: 0},
				insertLineAfter: true,
				insertLineBefore: true
			}
		}
	}
}

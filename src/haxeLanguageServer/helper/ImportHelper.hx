package haxeLanguageServer.helper;

import haxe.Json;
import haxe.display.JsonModuleTypes;
import haxeLanguageServer.Configuration.FunctionFormattingConfig;
import haxeLanguageServer.Configuration.ImportStyle;
import haxeLanguageServer.protocol.DisplayPrinter;
import tokentree.TokenTree;

using Lambda;
using tokentree.TokenTreeAccessHelper;

typedef ImportPosition = {
	final position:Position;
	final insertLineBefore:Bool;
	final insertLineAfter:Bool;
}

function createImportsEdit(doc:HxTextDocument, result:ImportPosition, paths:Array<String>, style:ImportStyle):TextEdit {
	if (style == Module) {
		paths = paths.map(TypeHelper.getModule);
	}
	final importData = {
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

function createFunctionImportsEdit<T>(doc:HxTextDocument, result:ImportPosition, context:Context, type:JsonType<T>,
		formatting:FunctionFormattingConfig):Array<TextEdit> {
	final importConfig = context.config.user.codeGeneration.imports;
	if (!importConfig.enableAutoImports) {
		return [];
	}
	var paths = [];
	final signature = type.extractFunctionSignatureOrThrow();
	if (formatting.argumentTypeHints && (!formatting.useArrowSyntax || signature.args.length != 1)) {
		paths = paths.concat(signature.args.map(arg -> arg.t.resolveImports()).flatten().array());
	}
	if (formatting.shouldPrintReturn(signature)) {
		paths = paths.concat(signature.ret.resolveImports());
	}
	paths = paths.filterDuplicates((e1, e2) -> Json.stringify(e1) == Json.stringify(e2));

	return if (paths.length == 0) {
		[];
	} else {
		final printer = new DisplayPrinter(false, Always);
		[createImportsEdit(doc, result, paths.map(printer.printPath), importConfig.style)];
	}
}

function determineImportPosition(document:HaxeDocument):ImportPosition {
	function defaultResult():ImportPosition {
		return {
			position: {line: 0, character: 0},
			insertLineAfter: true,
			insertLineBefore: true
		}
	}
	final tokens = document.tokens;
	if (tokens == null) {
		return defaultResult();
	}

	var firstImport:Null<TokenTree> = null;
	var packageStatement:Null<TokenTree> = null;

	// if the first token in the file is a comment, we should add the import after this
	final firstComment = if (tokens.list[0].tok.match(Comment(_))) {
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
		return SkipSubtree;
	});

	return if (firstImport != null) {
		{
			position: document.positionAt(tokens.getPos(firstImport).min),
			insertLineBefore: false,
			insertLineAfter: false
		}
	} else if (packageStatement != null) {
		final lastChild = packageStatement.getLastChild();
		final tokenPos = tokens.getPos(if (lastChild != null) lastChild else packageStatement);
		final pos = document.positionAt(tokenPos.max);
		pos.line += 1;
		pos.character = 0;
		{
			position: pos,
			insertLineAfter: true,
			insertLineBefore: true
		}
	} else if (firstComment != null) {
		final pos = document.positionAt(firstComment.pos.max);
		pos.line += 1;
		pos.character = 0;
		{
			position: pos,
			insertLineAfter: true,
			insertLineBefore: true
		}
	} else {
		defaultResult();
	}
}

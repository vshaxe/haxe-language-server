package haxeLanguageServer.features.haxe.codeAction;

import haxe.Json;
import haxeLanguageServer.documents.HaxeDocument;
import jsonrpc.Protocol;
import testcases.TestTextEditHelper;

class ExtractConstantFeatureTest extends Test implements IExtractConstantFeatureCases {
	function goldCheck(fileName:String, input:String, gold:String, config:String) {
		final range:Range = Json.parse(config);
		if (range.end == null)
			range.end = {line: range.start.line, character: range.start.character};

		final edits:Array<TextEdit> = makeEdits(input, fileName, range);
		final goldEdit:TextDocumentEdit = Json.parse(gold);
		Assert.notNull(goldEdit);
		TestTextEditHelper.compareTextEdits(goldEdit.edits, edits);
	}

	@:access(haxeLanguageServer.features.haxe.codeAction.ExtractConstantFeature)
	function makeEdits(content:String, fileName:String, range:Range):Array<TextEdit> {
		final context = new Context(new Protocol((_, _) -> {}));
		final uri = new DocumentUri("file://" + fileName + ".edittest");
		final doc = new HaxeDocument(uri, "haxe", 4, content);

		final extractConst = new ExtractConstantFeature(context);

		final actions:Array<CodeAction> = extractConst.extractConstant(doc, uri, range);
		Assert.equals(1, actions.length);
		Assert.notNull(actions[0].edit);
		@:nullSafety(Off) {
			Assert.notNull(actions[0].edit.documentChanges);
			Assert.equals(1, actions[0].edit.documentChanges.length);

			final docEdit:TextDocumentEdit = actions[0].edit.documentChanges[0];
			return docEdit.edits;
		}
	}
}

@:autoBuild(testcases.EditTestCaseMacro.build("test/testcases/extractConstant"))
private interface IExtractConstantFeatureCases {}

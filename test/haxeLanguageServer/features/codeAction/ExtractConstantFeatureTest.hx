package haxeLanguageServer.features.codeAction;

import haxe.Json;
import haxeLanguageServer.documents.HaxeDocument;
import jsonrpc.Protocol;
import testcases.TestTextEditHelper;

class ExtractConstantFeatureTest extends Test implements IExtractConstantFeatureCases {
	function goldCheck(fileName:String, input:String, gold:String, config:String) {
		var range:Range = Json.parse(config);
		if (range.end == null)
			range.end = {line: range.start.line, character: range.start.character};

		var edits:Array<TextEdit> = makeEdits(input, fileName, range);
		var goldEdit:TextDocumentEdit = Json.parse(gold);
		Assert.notNull(goldEdit);
		TestTextEditHelper.compareTextEdits(goldEdit.edits, edits);
	}

	@:access(haxeLanguageServer.features.codeAction.ExtractConstantFeature)
	function makeEdits(content:String, fileName:String, range:Range):Array<TextEdit> {
		var context = new TestContext(new Protocol(null));
		var uri = new DocumentUri("file://" + fileName + ".edittest");
		var doc = new HaxeDocument(context, uri, "haxe", 4, content);

		var extractConst:ExtractConstantFeature = new ExtractConstantFeature(context);

		var actions:Array<CodeAction> = extractConst.internalExtractConstant(doc, uri, range);
		Assert.equals(1, actions.length);

		var docEdit:TextDocumentEdit = cast actions[0].edit.documentChanges[0];
		return docEdit.edits;
	}
}

@:autoBuild(testcases.EditTestCaseMacro.build("test/testcases/extractConstant"))
private interface IExtractConstantFeatureCases {}

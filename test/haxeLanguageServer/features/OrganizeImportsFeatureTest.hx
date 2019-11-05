package haxeLanguageServer.features;

import haxe.Json;
import haxeLanguageServer.Configuration;
import jsonrpc.Protocol;
import testcases.IFileBasedEditTestCases;

class OrganizeImportsFeatureTest extends Test implements IOrganizeImportsFeatureTestCases {
	function goldCheck(fileName:String, input:String, gold:String, config:String) {
		var userConfig:UserConfig = Json.parse(config);
		var importsSortOrder:ImportsSortOrderConfig = AllAlphabetical;
		if ((userConfig != null) && (userConfig.importsSortOrder != null))
			importsSortOrder = userConfig.importsSortOrder;

		var edits:Array<TextEdit> = makeEdits(input, fileName, importsSortOrder);
		var goldEdit:TextDocumentEdit = Json.parse(gold);

		Assert.notNull(goldEdit);
		Assert.notNull(goldEdit.edits);
		Assert.equals(goldEdit.edits.length, edits.length);

		for (index in 0...goldEdit.edits.length) {
			var expectedEdit:TextEdit = goldEdit.edits[index];
			var actualEdit:TextEdit = edits[index];

			Assert.equals(expectedEdit.newText, actualEdit.newText);

			if (expectedEdit.range != null) {
				Assert.equals(expectedEdit.range.start.line, actualEdit.range.start.line);
				Assert.equals(expectedEdit.range.start.character, actualEdit.range.start.character);
				Assert.equals(expectedEdit.range.end.line, actualEdit.range.end.line);
				Assert.equals(expectedEdit.range.end.character, actualEdit.range.end.character);
			}
		}
	}

	@:access(haxeLanguageServer.Configuration)
	function makeEdits(content:String, fileName:String, importsSortOrder:ImportsSortOrderConfig):Array<TextEdit> {
		var context:Context = new Context(new Protocol(null));
		context.config.user = {
			importsSortOrder: importsSortOrder
		};
		var doc = new TextDocument(context, new DocumentUri("file://" + fileName + ".hxtest"), "haxe", 4, content);
		return OrganizeImportsFeature.organizeImports(doc, context, []);
	}
}

@:autoBuild(EditTestCaseMacro.build("test/testcases/organizeImports"))
private interface IOrganizeImportsFeatureTestCases {}

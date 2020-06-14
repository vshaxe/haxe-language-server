package haxeLanguageServer.features.codeAction;

import haxe.Json;
import haxeLanguageServer.Configuration;
import haxeLanguageServer.documents.TextDocument;
import jsonrpc.Protocol;
import testcases.TestTextEditHelper;

class OrganizeImportsFeatureTest extends Test implements IOrganizeImportsFeatureTestCases {
	function goldCheck(fileName:String, input:String, gold:String, config:String) {
		var userConfig:UserConfig = Json.parse(config);
		var importsSortOrder:ImportsSortOrderConfig = AllAlphabetical;
		if (userConfig != null && userConfig.importsSortOrder != null)
			importsSortOrder = userConfig.importsSortOrder;

		var edits:Array<TextEdit> = makeEdits(input, fileName, importsSortOrder);
		var goldEdit:TextDocumentEdit = Json.parse(gold);

		Assert.notNull(goldEdit);
		TestTextEditHelper.compareTextEdits(goldEdit.edits, edits);
	}

	@:access(haxeLanguageServer.Configuration)
	function makeEdits(content:String, fileName:String, importsSortOrder:ImportsSortOrderConfig):Array<TextEdit> {
		var context = new Context(new Protocol(null));
		context.config.user = {
			importsSortOrder: importsSortOrder
		};
		var doc = new TextDocument(context, new DocumentUri("file://" + fileName + ".edittest"), "haxe", 4, content);
		return OrganizeImportsFeature.organizeImports(doc, context, []);
	}
}

@:autoBuild(testcases.EditTestCaseMacro.build("test/testcases/organizeImports"))
private interface IOrganizeImportsFeatureTestCases {}

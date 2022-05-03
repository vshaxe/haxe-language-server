package haxeLanguageServer.features.haxe.codeAction;

import haxe.Json;
import haxeLanguageServer.Configuration;
import haxeLanguageServer.documents.HaxeDocument;
import jsonrpc.Protocol;
import testcases.TestTextEditHelper;

class OrganizeImportsFeatureTest extends Test implements IOrganizeImportsFeatureTestCases {
	function goldCheck(fileName:String, input:String, gold:String, config:String) {
		final userConfig:UserConfig = Json.parse(config);
		var importsSortOrder:ImportsSortOrderConfig = AllAlphabetical;
		if (userConfig != null && userConfig.importsSortOrder != null)
			importsSortOrder = userConfig.importsSortOrder;

		final edits:Array<TextEdit> = makeEdits(input, fileName, importsSortOrder);
		final goldEdit:TextDocumentEdit = Json.parse(gold);

		Assert.notNull(goldEdit);
		TestTextEditHelper.compareTextEdits(goldEdit.edits, edits);
	}

	@:access(haxeLanguageServer.Configuration)
	function makeEdits(content:String, fileName:String, importsSortOrder:ImportsSortOrderConfig):Array<TextEdit> {
		final context = new Context(new Protocol((_, _) -> {}));
		final settings = cast Reflect.copy(Configuration.DefaultUserSettings);
		settings.importsSortOrder = importsSortOrder;
		context.config.user = settings;
		final doc = new HaxeDocument(new DocumentUri("file://" + fileName + ".edittest"), "haxe", 4, content);
		return OrganizeImportsFeature.organizeImports(doc, context, []);
	}
}

@:autoBuild(testcases.EditTestCaseMacro.build("test/testcases/organizeImports"))
private interface IOrganizeImportsFeatureTestCases {}

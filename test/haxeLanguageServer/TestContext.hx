package haxeLanguageServer;

import haxeLanguageServer.features.codeAction.CodeActionFeature.CodeActionContributor;

class TestContext extends Context {
	public function new(languageServerProtocol) {
		super(languageServerProtocol);
	}

	override public function registerCodeActionContributor(contributor:CodeActionContributor) {}
}

package haxeLanguageServer.features;

import haxeLanguageServer.tokentree.SyntaxModernizer;

class CodeGenerationFeature {
	final context:Context;

	public function new(context:Context) {
		this.context = context;
		#if debug
		context.registerCodeActionContributor(modernizeSyntax);
		#end
	}

	function modernizeSyntax(params:CodeActionParams):Array<CodeAction> {
		var doc = context.documents.getHaxe(params.textDocument.uri);
		if (doc == null) {
			return [];
		}
		return try {
			new SyntaxModernizer(doc).resolve();
		} catch (e) {
			[];
		}
	}
}

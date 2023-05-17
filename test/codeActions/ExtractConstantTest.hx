package codeActions;

import haxeLanguageServer.features.haxe.codeAction.ExtractConstantFeature;

@:access(haxeLanguageServer.features.haxe.codeAction.ExtractConstantFeature)
class ExtractConstantTest extends DisplayTestCase {
	/**
		class Main {
			function makeEdits(content:String, fileName:String, range:Range):Array<TextEdit> {
				var context:Context = new Context(new Protocol(null));
				var uri:DocumentUri = new DocumentUri("{-1-}file://" + fileName + ".edittest");
				var doc = new TextDocument(context, uri, "haxe", 4, content);
				return docEdit.edits;
			}
		}
		---
		class Main {
			static inline final FILE = "file://";

			function makeEdits(content:String, fileName:String, range:Range):Array<TextEdit> {
				var context:Context = new Context(new Protocol(null));
				var uri:DocumentUri = new DocumentUri(FILE + fileName + ".edittest");
				var doc = new TextDocument(context, uri, "haxe", 4, content);
				return docEdit.edits;
			}
		}
	**/
	function testFile() {
		final extractConst = new ExtractConstantFeature(ctx.context);
		final actions:Array<CodeAction> = extractConst.extractConstant(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		class Main {
			function makeEdits(content:String, fileName:String, range:Range):Array<TextEdit> {
				var context:Context = new Context(new Protocol(null));
				var uri:DocumentUri = new DocumentUri("file://" + fileName + ".edittest");
				var doc = new TextDocument(context, uri, "{-1-}haxe", 4, content);
				var docEdit:TextDocumentEdit = cast actions[0].edit.documentChanges[0];
				return docEdit.edits;
			}
		}
		---
		class Main {
			static inline final HAXE = "haxe";

			function makeEdits(content:String, fileName:String, range:Range):Array<TextEdit> {
				var context:Context = new Context(new Protocol(null));
				var uri:DocumentUri = new DocumentUri("file://" + fileName + ".edittest");
				var doc = new TextDocument(context, uri, HAXE, 4, content);
				var docEdit:TextDocumentEdit = cast actions[0].edit.documentChanges[0];
				return docEdit.edits;
			}
		}
	**/
	function testHaxe() {
		final extractConst = new ExtractConstantFeature(ctx.context);
		final actions:Array<CodeAction> = extractConst.extractConstant(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		class Main {
			function makeEdits(content:String, fileName:String, range:Range):Array<TextEdit> {
				var context:Context = new Context(new Protocol(null));
				var uri:DocumentUri = new DocumentUri("file://" + fileName + ".edittest");
				var doc = new TextDocument(context, uri, '{-1-}haxe', 4, content);
				var docEdit:TextDocumentEdit = cast actions[0].edit.documentChanges[0];
				return docEdit.edits;
			}
		}
		---
		class Main {
			static inline final HAXE = 'haxe';

			function makeEdits(content:String, fileName:String, range:Range):Array<TextEdit> {
				var context:Context = new Context(new Protocol(null));
				var uri:DocumentUri = new DocumentUri("file://" + fileName + ".edittest");
				var doc = new TextDocument(context, uri, HAXE, 4, content);
				var docEdit:TextDocumentEdit = cast actions[0].edit.documentChanges[0];
				return docEdit.edits;
			}
		}
	**/
	function testHaxeSingleQuote() {
		final extractConst = new ExtractConstantFeature(ctx.context);
		final actions:Array<CodeAction> = extractConst.extractConstant(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		class Main {
			function init() {
				new JQuery ("#id1").removeClass ("disabled{-1-}");
				new JQuery ("#id1").prop ("readonly", false);

				new JQuery ("#id2").removeClass ("disabled");
				new JQuery ("#id2").prop ("readonly", false);
			}
		}
		---
		class Main {
			static inline final DISABLED = "disabled";

			function init() {
				new JQuery ("#id1").removeClass (DISABLED);
				new JQuery ("#id1").prop ("readonly", false);

				new JQuery ("#id2").removeClass (DISABLED);
				new JQuery ("#id2").prop ("readonly", false);
			}
		}
	**/
	function testMultiple() {
		final extractConst = new ExtractConstantFeature(ctx.context);
		final actions:Array<CodeAction> = extractConst.extractConstant(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}

	/**
		// öäüßł€µ”„¢«»æſðđŋħ̣ĸħĸĸ̣
		class Main {
			function init() {
				new JQuery ("#id1").removeClass ("disabled");
				new JQuery ("#id1").prop ("readonly", false);
				// öäüßł€µ”„¢«»æſðđŋħ̣ĸħĸĸ̣
				new JQuery ("#id2").removeClass ("{-1-}disabled{-2-}");
				new JQuery ("#id2").prop ("readonly", false);
			}
		}
		---
		// öäüßł€µ”„¢«»æſðđŋħ̣ĸħĸĸ̣
		class Main {
			static inline final DISABLED = "disabled";

			function init() {
				new JQuery ("#id1").removeClass (DISABLED);
				new JQuery ("#id1").prop ("readonly", false);
				// öäüßł€µ”„¢«»æſðđŋħ̣ĸħĸĸ̣
				new JQuery ("#id2").removeClass (DISABLED);
				new JQuery ("#id2").prop ("readonly", false);
			}
		}
	**/
	function testUmlautBeginAndEnd() {
		var prevContent = ctx.doc.content;
		final extractConst = new ExtractConstantFeature(ctx.context);
		final actions:Array<CodeAction> = extractConst.extractConstant(ctx.doc, ctx.uri, pos(1).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);

		ctx.doc.content = prevContent;
		final actions:Array<CodeAction> = extractConst.extractConstant(ctx.doc, ctx.uri, pos(2).toRange());
		applyTextEdit(actions[0].edit);
		eq(ctx.result, ctx.doc.content);
	}
}

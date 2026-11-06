package haxeLanguageServer.features;

import haxe.display.Display;
import haxeLanguageServer.features.haxe.completion.CompletionContextData;
import haxeLanguageServer.features.haxe.completion.CompletionFeature;
import haxeLanguageServer.protocol.DisplayPrinter;

@:access(haxeLanguageServer.features.haxe.completion.CompletionFeature)
class CompletionFeatureTest extends Test {
	// Completion item for `?"inline":Int`, as sent by the compiler
	static final inlineItem = '{"kind":"ClassField","args":{"field":{"name":"inline","type":{"kind":"TAbstract","args":{"path":{"typeName":"Null","moduleName":"StdTypes","pack":[]},"params":[{"kind":"TAbstract","args":{"path":{"typeName":"Int","moduleName":"StdTypes","pack":[]},"params":[]}}]}},"isPublic":true,"isFinal":false,"isAbstract":false,"params":[],"meta":[{"name":":optional","args":[],"pos":{"file":"?","min":-1,"max":-1}}],"kind":{"kind":"FVar","args":{"read":{"kind":"AccNormal"},"write":{"kind":"AccNormal"}}},"expr":null,"pos":{"file":"Main.hx","min":0,"max":0},"doc":null,"overloads":[],"scope":1},"origin":{"kind":0,"args":{"kind":"typedef","pack":[],"name":"T","moduleName":"Main","pos":{"file":"Main.hx","min":0,"max":47},"isPrivate":false,"params":[],"meta":[],"doc":null,"args":{"type":{"kind":"TAnonymous","args":{"fields":[{"name":"inline","type":{"kind":"TAbstract","args":{"path":{"typeName":"Null","moduleName":"StdTypes","pack":[]},"params":[{"kind":"TAbstract","args":{"path":{"typeName":"Int","moduleName":"StdTypes","pack":[]},"params":[]}}]}},"isPublic":true,"isFinal":false,"isAbstract":false,"params":[],"meta":[{"name":":optional","args":[],"pos":{"file":"?","min":-1,"max":-1}}],"kind":{"kind":"FVar","args":{"read":{"kind":"AccNormal"},"write":{"kind":"AccNormal"}}},"expr":null,"pos":{"file":"Main.hx","min":13,"max":31},"doc":null,"overloads":[],"scope":1},{"name":"block","type":{"kind":"TAbstract","args":{"path":{"typeName":"Int","moduleName":"StdTypes","pack":[]},"params":[]}},"isPublic":true,"isFinal":false,"isAbstract":false,"params":[],"meta":[],"kind":{"kind":"FVar","args":{"read":{"kind":"AccNormal"},"write":{"kind":"AccNormal"}}},"expr":null,"pos":{"file":"Main.hx","min":32,"max":46},"doc":null,"overloads":[],"scope":1}],"status":{"kind":"AClosed"}}}}}},"resolution":{"isQualified":true,"qualifier":"this"}},"type":{"kind":"TAbstract","args":{"path":{"pack":[],"moduleName":"StdTypes","typeName":"Null","importStatus":0},"params":[{"kind":"TAbstract","args":{"path":{"pack":[],"moduleName":"StdTypes","typeName":"Int","importStatus":0},"params":[]}}]}},"index":1}';

	function item(name:String):DisplayItem<Dynamic> {
		final item:DisplayItem<Dynamic> = haxe.Json.parse(inlineItem);
		item.args.field.name = name;
		return item;
	}

	function complete(name:String, kind:CompletionModeKind<Dynamic>, lineAfter = "") {
		final feature = std.Type.createEmptyInstance(CompletionFeature);
		Reflect.setField(feature, "printer", new DisplayPrinter(false, Qualified, null));
		final data:CompletionContextData = cast {
			replaceRange: {start: {line: 0, character: 2}, end: {line: 0, character: 2}},
			mode: {kind: kind},
			lineAfter: lineAfter,
			isResolve: false
		};
		return feature.createClassFieldCompletionItem(item(name), data);
	}

	function text(item:languageServerProtocol.Types.CompletionItem):String {
		final edit:Dynamic = item.textEdit;
		return edit.newText;
	}

	function testKeywordFieldIsQuoted() {
		final field = complete("inline", Field);
		Assert.equals('"inline"', text(field));
		Assert.equals("inline", field.label);
		Assert.equals("inline", field.filterText);

		Assert.equals('"inline": ', text(complete("inline", StructureField)));
		Assert.equals('"inline":', text(complete("inline", Pattern)));
		Assert.equals('"inline"', text(complete("inline", StructureField, ":")));
	}

	function testRegularFieldIsUnchanged() {
		final field = complete("block", Field);
		Assert.equals("block", text(field));
		Assert.isNull(field.filterText);
		Assert.equals("block: ", text(complete("block", StructureField)));
	}
}

import haxe.display.Position.Range;
import haxeLanguageServer.documents.HaxeDocument;
import utest.Assert;

using Lambda;

@:autoBuild(BuildMacro.buildTestCase())
class DisplayTestCase implements utest.ITest {
	var ctx:DisplayTestContext;

	public function new() {}

	// api
	inline function pos(name)
		return ctx.pos(name);

	inline function range(id:Int, id2:Int):Range {
		return ctx.range(id, id2);
	}

	inline function getRegexRanges(regex:EReg):Array<Range> {
		return ctx.getRegexRanges(regex);
	}

	inline function rangeText(id:Int, id2:Int):String {
		return ctx.rangeText(id, id2);
	}

	public function codeActionParams(range:Range):CodeActionParams {
		return ctx.codeActionParams(range);
	}

	function createDiagnostic(range:Range, msg = ""):Diagnostic {
		return ctx.createDiagnostic(range, msg);
	}

	public function applyTextEdit(edit:WorkspaceEdit):Void {
		ctx.applyTextEdit(edit);
	}

	function assert(v:Bool)
		Assert.isTrue(v);

	function eq<T>(expected:T, actual:T, ?pos:haxe.PosInfos) {
		Assert.equals(expected, actual, pos);
	}

	function arrayEq<T>(expected:Array<T>, actual:Array<T>, ?pos:haxe.PosInfos) {
		Assert.same(expected, actual, pos);
	}

	function report(message, pos:haxe.PosInfos) {
		Assert.fail(message, pos);
	}
}

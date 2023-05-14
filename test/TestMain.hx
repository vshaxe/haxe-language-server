package;

import haxeLanguageServer.features.haxe.codeAction.*;
import haxeLanguageServer.helper.*;
import haxeLanguageServer.hxParser.*;
import haxeLanguageServer.protocol.*;
import haxeLanguageServer.tokentree.*;
import utest.Runner;
import utest.ui.Report;

class TestMain {
	static function main() {
		final cases = [
			new ArrayHelperTest(),
			new IdentifierHelperTest(),
			new ImportHelperTest(),
			new PathHelperTest(),
			new PositionHelperTest(),
			new RangeHelperTest(),
			new TypeHelperTest(),
			new RenameResolverTest(),
			new ExtensionsTest(),
			new ExtractConstantFeatureTest(),
			new OrganizeImportsFeatureTest(),
			new SemVerTest(),
			new TokenTreeTest()
		];
		var runner = new Runner();

		for (eachCase in cases) {
			runner.addCase(eachCase);
		}

		for (c in BuildMacro.getCases("codeActions")) {
			runner.addCase(c);
		}

		Report.create(runner);
		runner.run();
	}
}

package;

import haxeLanguageServer.features.codeAction.*;
import haxeLanguageServer.helper.*;
import haxeLanguageServer.hxParser.*;
import haxeLanguageServer.protocol.*;
import utest.UTest;

class TestMain {
	static function main() {
		// @formatter:off
		UTest.run([
			new ArrayHelperTest(),
			new IdentifierHelperTest(),
			new ImportHelperTest(),
			new PathHelperTest(),
			new PositionHelperTest(),
			new RangeHelperTest(),
			new TypeHelperTest(),
			new RenameResolverTest(), 
			new HelperTest(),
			new ExtractConstantFeatureTest(),
			new OrganizeImportsFeatureTest(),
			new SemVerTest()
		]);
		// @formatter:on
	}
}

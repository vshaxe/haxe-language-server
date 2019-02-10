package;

import utest.UTest;
import haxeLanguageServer.helper.*;
import haxeLanguageServer.hxParser.*;
import haxeLanguageServer.tokentree.*;
import haxeLanguageServer.protocol.helper.*;

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
			new TokenTreeTest()
		]);
		// @formatter:on
	}
}

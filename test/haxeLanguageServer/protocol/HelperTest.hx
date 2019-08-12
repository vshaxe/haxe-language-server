package haxeLanguageServer.protocol;

import haxe.display.JsonModuleTypes.ImportStatus;

using Lambda;

class HelperTest extends Test {
	function testResolveImports() {
		var imports = Helper.resolveImports({
			kind: TInst,
			args: {
				path: {
					typeName: "Vector",
					pack: ["haxe", "ds"],
					moduleName: "Vector",
					importStatus: Unimported
				},
				params: [
					{
						kind: TInst,
						args: {
							path: {
								typeName: "PosInfos",
								pack: ["haxe"],
								moduleName: "PosInfos",
								importStatus: Unimported
							}
						}
					}
				]
			}
		});
		Assert.equals(2, imports.length);
		Assert.isTrue(imports.exists(path -> path.typeName == "PosInfos"));
		Assert.isTrue(imports.exists(path -> path.typeName == "Vector"));
	}
}

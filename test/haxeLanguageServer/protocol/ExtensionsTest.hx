package haxeLanguageServer.protocol;

import haxe.display.JsonModuleTypes;

using Lambda;

class ExtensionsTest extends Test {
	function testResolveImports() {
		final imports = Extensions.resolveImports({
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

	function testRemoveNulls() {
		final result = Extensions.removeNulls({
			"kind": TAbstract,
			"args": {
				"path": {
					"typeName": "Null",
					"moduleName": "StdTypes",
					"pack": []
				},
				"params": [
					{
						"kind": TInst,
						"args": {
							"path": {
								"typeName": "String",
								"moduleName": "String",
								"pack": []
							},
							"params": []
						}
					}
				]
			}
		});
		Assert.isTrue(result.nullable);
		Assert.equals("String", result.type.args.path.typeName);
	}
}

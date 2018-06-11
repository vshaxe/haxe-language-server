package haxeLanguageServer.protocol.helper;

import haxe.display.JsonModuleTypes.ImportStatus;
using Lambda;

class HelperTest extends TestCaseBase {
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
        assertEquals(2, imports.length);
        assertTrue(imports.exists(path -> path.typeName == "PosInfos"));
        assertTrue(imports.exists(path -> path.typeName == "Vector"));
    }
}
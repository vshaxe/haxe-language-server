package;

import haxe.unit.TestRunner;

class TestMain {
    public function new() {
        var runner = new TestRunner();

        CompileTime.importPackage("haxeLanguageServer.helper");
        CompileTime.importPackage("haxeLanguageServer.features");

        var tests = CompileTime.getAllClasses(TestCaseBase);
        for (testClass in tests) runner.add(Type.createInstance(testClass, []));

        var success = runner.run();
        Sys.exit(if (success) 0 else 1);
    }

    static function main() {
        new TestMain();
    }
}
package haxeLanguageServer;

import haxe.unit.TestRunner;
import haxeLanguageServer.helper.ImportHelperTest;
import haxeLanguageServer.helper.PathHelperTest;

class TestMain {
    public function new() {
        var runner = new TestRunner();
        runner.add(new PathHelperTest());
        runner.add(new ImportHelperTest());
        var success = runner.run();
        Sys.exit(if (success) 0 else 1);
    }

    static function main() {
        new TestMain();
    }
}
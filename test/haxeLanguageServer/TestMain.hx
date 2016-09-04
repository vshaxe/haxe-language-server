package haxeLanguageServer;

import haxe.unit.TestRunner;
import haxeLanguageServer.helper.PathHelperTest;

class TestMain {
    public function new() {
        var runner = new TestRunner();
        runner.add(new PathHelperTest());
        var success = runner.run();
        Sys.exit(if (success) 0 else 1);
    }

    static function main() {
        new TestMain();
    }
}
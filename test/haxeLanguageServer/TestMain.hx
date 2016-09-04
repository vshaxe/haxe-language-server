package haxeLanguageServer;

import haxe.unit.TestRunner;
import haxeLanguageServer.helper.PathHelperTest;

class TestMain {
    public function new() {
        var runner = new TestRunner();
        runner.add(new PathHelperTest());
        runner.run();
    }

    static function main() {
        new TestMain();
    }
}
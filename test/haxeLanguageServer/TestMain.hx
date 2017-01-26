package haxeLanguageServer;

import haxe.unit.TestRunner;
import haxeLanguageServer.helper.*;

class TestMain {
    public function new() {
        var runner = new TestRunner();
        runner.add(new PathHelperTest());
        runner.add(new ImportHelperTest());
        runner.add(new TypeHelperTest());
        runner.add(new ProtocolTypesHelperTest());
        var success = runner.run();
        Sys.exit(if (success) 0 else 1);
    }

    static function main() {
        new TestMain();
    }
}
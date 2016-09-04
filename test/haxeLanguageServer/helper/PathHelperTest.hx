package haxeLanguageServer.helper;

import haxe.unit.TestCase;

class PathHelperTest extends TestCase {
    public function testMatches() {
        function matches(filter:TestFilter, path:TestPath):Bool {
            var pathFilter = PathHelper.preparePathFilter(filter, TestPath.HaxelibPath, TestPath.WorkspaceRoot);
            return PathHelper.matches(path, pathFilter);
        }
        function match(filter:TestFilter, path:TestPath) assertTrue(matches(filter, path));
        function fail(filter:TestFilter, path:TestPath) assertFalse(matches(filter, path));

        match(WorkspaceRoot, WorkspaceRoot);
        match(WorkspaceSource, WorkspaceSource);
        fail(WorkspaceSource, WorkspaceExport);

        match(HaxelibPath, HaxelibPath);
        match(Flixel, FlxG);
        match(FlixelOrLime, FlxG);
        match(FlixelOrLime, LimeSystem);
        fail(FlixelOrLime, Hscript);

        match(MatchAll, WorkspaceRoot);
        match(MatchAll, WorkspaceSource);
        match(MatchAll, WorkspaceExport);
        match(MatchAll, HaxelibPath);
        match(MatchAll, FlxG);
        match(MatchAll, LimeSystem);
        match(MatchAll, Hscript);
        match(MatchAll, LinuxPath);
    }

    public function testNormalize() {
        function test(expected:String, path:String) assertEquals(expected, PathHelper.normalize(path));

        test("c:/HaxeToolkit/haxe", "C:\\HaxeToolkit\\haxe");
        test("c:/HaxeToolkit/haxe", "c:/HaxeToolkit/haxe");
        test("/usr/bin", "/usr/bin");
    }
}

@:enum abstract TestFilter(String) to String {
    var WorkspaceRoot = "${workspaceRoot}";
    var WorkspaceSource = WorkspaceRoot + "/source";

    var HaxelibPath = "${haxelibPath}";
    var Flixel = HaxelibPath + "\\flixel";
    var FlixelOrLime = HaxelibPath + "/(flixel|lime)";

    var MatchAll = ".*?";
}

@:enum abstract TestPath(String) to String {
    var WorkspaceRoot = "c:/projects/vshaxe";
    var WorkspaceSource = WorkspaceRoot + "/source";
    var WorkspaceExport = WorkspaceRoot + "/export";

    var HaxelibPath = "C:\\HaxeToolkit\\haxe\\lib";
    var FlxG = HaxelibPath + "/flixel/git/flixel/FlxG.hx";
    var LimeSystem = HaxelibPath + "/lime/2,9,1/lime/system/System.hx";
    var Hscript = HaxelibPath + "/hscript/2,0,7/hscript/";

    var LinuxPath = "~/../../../lib/";
}
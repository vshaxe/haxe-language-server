package haxeLanguageServer.hxParser;

import haxeLanguageServer.TextDocument;

class LocalUsageResolverTest extends TestCaseBase {
    function check(code:String) {
        var expectedUsages = findMarkedRanges(code, "%");
        var declaration = expectedUsages[0];

        code = code.replace("%", "");

        var resolver = new LocalUsageResolver(declaration);
        resolver.walkFile(new TextDocument(new DocumentUri(
            "file:///c:/"), "haxe", 0, code).parseTree, Root);
        var actualUsages = resolver.usages;

        function fail() {
            throw 'Expected ${expectedUsages.length} renames but was ${actualUsages.length}';
        }

        if (expectedUsages.length != actualUsages.length) {
            fail();
        } else {
            for (i in 0...expectedUsages.length) {
                if (!expectedUsages[i].isEqual(actualUsages[i])) {
                    fail();
                }
            }
        }
        currentTest.done = true;
    }

    function findMarkedRanges(code:String, marker:String):Array<Range> {
        // not expecting multiple marked words in a single line..
        var lineNumber = 0;
        var ranges = [];
        for (line in code.split("\n")) {
            var startChar = line.indexOf(marker);
            var endChar = line.lastIndexOf(marker);
            if (startChar != -1 && endChar != -1) {
                ranges.push({
                    start: {line: lineNumber, character: startChar},
                    end: {line: lineNumber, character: endChar - 1}
                });
            }
            lineNumber++;
        }
        return ranges;
    }

    function testFindLocalVarUsages() {
        check("
class Foo {
    function foo() {
        var %bar%;
        %bar%;
    }
}");
    }

    function testFindParameterUsages() {
        check("
class Foo {
    function foo(%bar%:Int) {
        %bar%;
    }
}");
    }

    function testDifferentScopes() {
        check("
class Foo {
    function f1() {
        var %bar%;
        %bar%;
    }

    function f2() {
        bar;
    }
}");
    }

    function testParameterScope() {
        check("
class Foo {
    function foo(%bar%:Int) {
        %bar%;
    }

    function f2() {
        bar;
    }
}");
    }

    function testShadowing() {
        check("
class Foo {
    function foo() {
        var %bar%;
        %bar%;

        var bar;
        bar;
    }
}");
    }

    function testNestedShadowing() {
        check("
class Foo {
    function foo() {
        var %bar%;
        %bar%;

        {
            var bar;
            bar;

            {
                var bar;
                bar;
            }

            var bar;
            bar;
        }

        %bar%;
    }
}");
    }

    function testForLoopShadowing() {
        check("
class Foo {
    function foo() {
        var %bar%;
        %bar%;

        for (bar in a) {}

        %bar%;
    }
}");
    }

    function testParameterShadowing() {
        check("
class Foo {
    function foo() {
        var %bar%;
        %bar%;

        function foo2(bar) {
            bar;
        }

        %bar%
    }
}");
    }

    function testCaseShadowing() {
        check("
class Foo {
    function foo() {
        var %bar%;
        %bar%;

        switch (foo) {
            case _:
                var bar;
                bar;
        }

        %bar%
    }
}");
    }

    function testCaptureVariableShadowing() {
        check("
class Foo {
    function foo() {
        var %bar%;
        %bar%;

        switch (foo) {
            case bar:
                bar;
            case Foo(_.toLowerCase() => bar):
                bar;
        }

        %bar%
    }
}");
    }

    function testDollarIdent() {
        check("
class Foo {
    function foo() {
        var %bar%;
        macro $%bar%;
    }
}");
    }
}
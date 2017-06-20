package haxeLanguageServer.hxParser;

import haxeLanguageServer.TextDocument;

class RenameResolverTest extends TestCaseBase {
    function check(code:String) {
        var markedUsages = findMarkedRanges(code, "%");
        var declaration = markedUsages[0];

        code = code.replace("%", "");

        var expectedEdits = [for (usage in markedUsages) {
            range: usage,
            newText: "new"
        }];

        var resolver = new RenameResolver(declaration, "new");
        resolver.walkFile(new TextDocument(new DocumentUri(
            "file:///c:/"), "haxe", 0, code).parseTree, Root);

        assertEquals(applyEdits(code, expectedEdits), applyEdits(code, resolver.edits));
    }

    function applyEdits(document:String, edits:Array<TextEdit>):String {
        edits = edits.copy();
        var lines = ~/\n\r?/g.split(document);
        for (i in 0...lines.length) {
            var line = lines[i];
            var relevantEdits = edits.filter(edit -> edit.range.start.line == i);
            for (edit in relevantEdits) {
                var range = edit.range;
                lines[i] = line.substr(0, range.start.character) + edit.newText + line.substring(range.end.character);
                edits.remove(edit);
            }
        }
        return lines.join("\n");
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

    function testRenameWithSwitch() {
        check("
class Foo {
    function foo() {
        var %bar%;
        %bar%;

        switch (foo) {
            case _:
                %bar%;
        }
    }
}");
    }
}
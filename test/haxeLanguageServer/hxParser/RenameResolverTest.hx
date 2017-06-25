package haxeLanguageServer.hxParser;

import haxeLanguageServer.TextDocument;

class RenameResolverTest extends TestCaseBase {
    function check(code:String, ?expected:String) {
        var markedUsages = findMarkedRanges(code, "%");
        var declaration = markedUsages[0];
        if (declaration == null) {
            throw "missing declaration markers";
        }
        code = code.replace("%", "");

        var newName = "newName";
        var resolver = new RenameResolver(declaration, newName);
        var parseTree = new TextDocument(new DocumentUri("file:///c:/"), "haxe", 0, code).parseTree;
        resolver.walkFile(parseTree, Root);

        if (expected == null) {
            var expectedEdits = [for (usage in markedUsages) {
                range: usage,
                newText: newName
            }];
            expected = applyEdits(code, expectedEdits);
        }

        assertEquals(expected, applyEdits(code, resolver.edits));
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

        for (bar in a) {
            bar;
        }

        %bar%;
    }
}");
    }

    function testCatchVariableShadowing() {
        check("
class Foo {
    function foo() {
        var %bar%;
        %bar%;

        try {}
        catch (bar:Any) {
            bar;
        }

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

    function testDollarDotIdent() {
        check("
class Foo {
    function foo() {
        var %field%;
        macro { $struct.$%field%; }
    }
}");
    }

    function testRegularDotIdent() {
        check("
class Foo {
    function foo() {
        var %field%;
        struct.field;
    }
}");
    }

    function testDollarObjectField() {
        check("
class Foo {
    function foo() {
        var %name%;
        macro { $%name%: 1 }
    }
}");
    }

    function testRegularObjectField() {
        check("
class Foo {
    function foo() {
        var %name%;
        { name: 1 }
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

    function testAvoidConflict() {
        check("
class Foo {
    function foo() {
        var %bar%;
        newName;
    }
}", "
class Foo {
    function foo() {
        var newName;
        this.newName;
    }
}"
);
    }

    function testAvoidConflictStatic() {
        check("
class Foo {
    static function foo() {
        var %bar%;
        newName;
    }
}", "
class Foo {
    static function foo() {
        var newName;
        Foo.newName;
    }
}"
);
    }

    function testDontAvoidConflict() {
        check("
class Foo {
    function foo() {
        var %bar%;
        {
            var newName;
            newName;
        }
        %bar%;
        newName;
    }
}","
class Foo {
    function foo() {
        var newName;
        {
            var newName;
            newName;
        }
        newName;
        this.newName;
    }
}");
    }

    function testDuplicatedCaptureVariable() {
        check("
class Foo {
    function foo() {
        switch (foo) {
            case Foo(%bar%) |
                 Bar(%bar%) |
                 FooBar(%bar%):
                %bar%;
        }
    }
}");
    }

    function testDuplicatedCaptureVariableDifferentScopes() {
        check("
class Foo {
    function foo() {
        switch (foo) {
            case Foo(%bar%):
                switch (foo) {
                    case Foo(bar):
                        bar;
            }
            %bar%;
        }
    }
}");
    }
}

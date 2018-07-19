abstract Abstract<TAbstract>(Int) {
    inline static var CONSTANT = 5;

    @:op(A * B)
    public function repeat(rhs:Int):Abstract {
        return this * rhs;
    }

    @:op(A + B) function add(rhs:Int):Abstract;

    @:arrayAccess
    public inline function get(key:Int) {
        return 0;
    }

    @:resolve
    function resolve(name:String) {
        return null;
    }

    public function new() {}

    function foo<TAbstractField>() {}
}

class Class<TClass1, TClass2> {
    inline static var CONSTANT = 5;

    var variable:Int;

    var variableWithBlockInit:Int = {
        function foo():Int return 0;
        var bar = foo();
        bar;
    };

    var property(default,null):Int;

    final finaleVariable:Int;

    final function finalMethod():Void {}

    @:op(A + B)
    public function fakeAdd(rhs:Int):Int {
        return 0;
    }

    /**



    **/
    function foo<TClassField>(param1:Int, param2:Int) {
        "


        ";

        function foo2<TLocalFunction>() {
            function foo3() {
                var foo4:Int;
            }
        }

        inline function innerFoo() {}

        var f = function() {}

        var a, b, c = {
            var f:Int = 100;
            f;
        };

        var array = [];
        for (element in array) {
            var varInFor;
        }

        try {}
        catch (exception:Any) {
            var varInCatch;
        }

        macro class MacroClass {
            var macroField:Int;
        }

        macro class {
            var macroField:Int;
        }

        // inserted _ name shouldn't appear
        var
        // and also shouldn't affect positions
        var var maybeIncorrectPos:Int;
    }

    function new() {}
}

interface Interface<TInterface> {
    var variable:Int;
    function foo<TInterfaceField>():Void;
}

@:enum abstract EnumAbstract(Int) {
    function foo() {
        macro class MacroClass {
            var macroField:Int;

            function macroFunction() {
                var macroVar;
            }
        }
    }

    inline static var CONSTANT = 5;

    var Value1 = 0;
    var Value2 = 1;

    @:op(A + B) function add(rhs:Int):Abstract;
}

enum abstract EnumAbstractHaxe4(Int) {
    inline static var CONSTANT = 5;

    var Value1 = 0;
    var Value2 = 1;
}

enum Enum<TEnum> {
    Simple;
    Complex<TEnumField>(i:Int, b:Bool);
}

typedef TypeAlias<TTypedef> = Int;

typedef TypedefShortFields = {
    ?a:Int,
    b:Bool
}

typedef TypedefComplexFields<Test> = {
    @:optional var a:Int;
    var b:Bool;
    var ?c:Bool;
    function foo(bar:Int):Void;
}

typedef TypedefExtension = {
    >Foo,
    ?a:Int,
    b:Bool
}

typedef TypedefExtension = A & B & {
    a:Bool
} & C {
    b:Int
}

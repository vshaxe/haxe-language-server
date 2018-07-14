package haxeLanguageServer.helper;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
using haxe.macro.TypeTools;

class StructDefaultsMacro {
    /**
        Assigns the values from `defaults` to `struct` if they are equal to `null`.

        `struct` and `defaults` are assumed to be structure types.
        Assignments are generated recursively for fields that themselves have a structure type.
    **/
    public static macro function applyDefaults(struct:Expr, defaults:Expr):Expr {
        inline function error(message:String)
            Context.fatalError(message, (macro 0).pos);

        var structType = Context.typeof(struct);
        var defaultsType = Context.typeof(defaults);
        if (!defaultsType.unify(structType))
            error("Arguments don't unify");

        var fields = getStructFields(structType);
        if (fields == null)
            error("Unable to retrieve struct fields");

        return macro $b {generateAssignments(fields, struct, defaults)};
    }

    static function generateAssignments(fields:Array<ClassField>, struct:Expr, defaults:Expr):Array<Expr> {
        var assignments = [];
        for (field in fields) {
            var name = field.name;
            assignments.push(macro {
                if ($struct.$name == null) $struct.$name = $defaults.$name;
            });

            // recurse
            switch (field.type) {
                case TType(_, params) | TAbstract(_, params) if (params.length > 0):
                    var innerFields = getStructFields(params[0]);
                    if (innerFields != null)
                        assignments = assignments.concat(generateAssignments(
                            innerFields,
                            macro {$struct.$name;},
                            macro {$defaults.$name;}
                        ));
                case _:
            }
        }
        return assignments;
    }

    static function getStructFields(type:Type):Array<ClassField> {
        return switch (type) {
            case TType(t, params):
                switch (t.get().type) {
                    case TAnonymous(a): a.get().fields;
                    case _: null;
                }
            case _: null;
        }
    }
}

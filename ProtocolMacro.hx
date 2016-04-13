import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
using haxe.macro.Tools;

class ProtocolMacro {
    static function build():Array<Field> {
        var fields = Context.getBuildFields();

        var requestCases = new Array<Case>();
        var notificationCases = new Array<Case>();

        var ab = switch (Context.getType("Protocol.Method").follow()) {
            case TAbstract(_.get() => ab, _): ab;
            default: throw false;
        }
        var abPath = ab.module.split(".");
        abPath.push(ab.name);
        for (method in ab.impl.get().statics.get()) {
            var methodNameExpr = macro $p{abPath.concat([method.name])};
            var handlerName = "on" + method.name;
            var handlerArgDefs = [];
            var handlerCallArgs = [];
            switch (method.type) {
                case TAbstract(_.get() => {name: "Method"}, [params, resultData, errorData]):
                    var paramsCT = params.toComplexType();
                    if (params.toString() != "Void") {
                        handlerArgDefs.push({name: "params", type: paramsCT});
                        handlerCallArgs.push(macro request.params);
                    }

                    handlerArgDefs.push({name: "cancel", type: macro : JsonRpc.CancelCallback});

                    var resultDataCT = resultData.toComplexType();
                    handlerArgDefs.push({name: "resolve", type: macro : $resultDataCT->Void});

                    var errorCT;
                    if (errorData.toString() == "Void") {
                        errorCT = macro : Int -> String -> Void;
                    } else {
                        var errorDataCT = errorData.toComplexType();
                        errorCT = macro : Int -> String -> $errorDataCT -> Void;
                    }
                    handlerArgDefs.push({name: "reject", type: errorCT});

                    handlerCallArgs.push(macro null);
                    handlerCallArgs.push(macro null);
                    handlerCallArgs.push(macro null);

                    requestCases.push({
                        values: [methodNameExpr],
                        expr: macro this.$handlerName($a{handlerCallArgs})
                    });
                case TAbstract(_.get() => {name: "Notification"}, [params]):
                    var paramsCT = params.toComplexType();
                    if (params.toString() != "Void") {
                        handlerArgDefs.push({name: "params", type: paramsCT});
                        handlerCallArgs.push(macro notification.params);
                    }

                    fields.push({
                        pos: method.pos,
                        name: "send" + method.name,
                        access: [APublic],
                        kind: FFun({
                            ret: macro : Void,
                            args: [{name: "params", type: paramsCT}],
                            expr: macro {}
                        })
                    });

                    notificationCases.push({
                        values: [methodNameExpr],
                        expr: macro this.$handlerName($a{handlerCallArgs})
                    });
                default:
                    throw false;
            }
            fields.push({
                pos: method.pos,
                name: handlerName,
                access: [APublic,ADynamic],
                kind: FFun({
                    ret: macro : Void,
                    args: handlerArgDefs,
                    expr: macro {}
                })
            });
        }

        for (field in fields) {
            switch [field.name, field.kind] {
                case ["handleRequest", FFun(fun)]:
                    fun.expr = {
                        expr: ESwitch(macro request.method, requestCases, macro throw "TODO: dispatch MethodNotFound"),
                        pos: field.pos
                    }
                case ["handleNotification", FFun(fun)]:
                    fun.expr = {
                        expr: ESwitch(macro notification.method, notificationCases, macro throw "TODO: dispatch MethodNotFound"),
                        pos: field.pos
                    }
                default:
            }
        }

        return fields;
    }
}

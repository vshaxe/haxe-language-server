import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
using haxe.macro.Tools;

class ProtocolMacro {
    static function build(methodType:String):Array<Field> {
        var fields = Context.getBuildFields();
        switch (Context.getType(methodType).follow()) {
            case TAbstract(_.get() => ab, _):
                var impl = ab.impl.get();
                for (method in impl.statics.get()) {
                    switch (method.type) {
                        case TAbstract(_, [params, result, errorData]):
                            var paramsCT = params.toComplexType();
                            var callbackCT;
                            if (result.toString() == "Void") {
                                callbackCT = macro : $paramsCT->Void;

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
                            } else {
                                var cancelCT = macro : JsonRpc.CancelCallback;
                                var resultCT = result.toComplexType();
                                var errorCT;
                                if (errorData.toString() == "Void") {
                                    errorCT = macro : Int -> String -> Void;
                                } else {
                                    var errorDataCT = errorData.toComplexType();
                                    errorCT = macro : Int -> String -> $errorDataCT -> Void;
                                }
                                callbackCT = macro : $paramsCT->$cancelCT->($resultCT->Void)->$errorCT->Void;
                            }
                            fields.push({
                                pos: method.pos,
                                name: "on" + method.name,
                                access: [APublic],
                                kind: FFun({
                                    ret: macro : Void,
                                    args: [{name: "callback", type: callbackCT}],
                                    expr: macro {}
                                })
                            });
                        default:
                            throw false;
                    };
                }
            default:
                throw "Invalid method type";
        }
        return fields;
    }
}

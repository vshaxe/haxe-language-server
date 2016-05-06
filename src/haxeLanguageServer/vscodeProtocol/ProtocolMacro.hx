package haxeLanguageServer.vscodeProtocol;

import haxe.macro.Context;
import haxe.macro.Expr;
using haxe.macro.Tools;

class ProtocolMacro {
    macro static function build():Array<Field> {
        var fields = Context.getBuildFields();

        var requestCases = new Array<Case>();
        var notificationCases = new Array<Case>();

        var cl = switch (Context.getType("ProtocolTypes.MethodNames").follow()) {
            case TInst(_.get() => cl, _): cl;
            default: throw false;
        }
        var clPath = cl.module.split(".");
        clPath.push(cl.name);
        for (method in cl.statics.get()) {
            var methodNameExpr = macro $p{clPath.concat([method.name])};
            var handlerName = "on" + method.name;
            var handlerArgDefs = [];
            var handlerCallArgs = [];
            switch (method.type) {
                case TAbstract(_.get() => {name: "RequestMethod"}, [params, resultData, errorData]):
                    var paramsCT = params.toComplexType();
                    if (params.toString() != "Void") {
                        handlerArgDefs.push({name: "params", type: paramsCT});
                        handlerCallArgs.push(macro request.params);
                    }

                    handlerArgDefs.push({name: "token", type: macro : jsonrpc.Protocol.CancellationToken});
                    handlerCallArgs.push(macro token);

                    var resultDataCT, resolveExpr;
                    if (resultData.toString() != "Void") {
                        resultDataCT = resultData.toComplexType();
                        resolveExpr = macro resolve;
                    } else {
                        resultDataCT = macro : Void;
                        resolveExpr = macro function() resolve(null);
                    }
                    handlerArgDefs.push({name: "resolve", type: macro : $resultDataCT->Void});
                    handlerCallArgs.push(resolveExpr);

                    var errorDataCT = errorData.toComplexType();
                    handlerArgDefs.push({name: "reject", type: macro : jsonrpc.Types.ResponseError<$errorDataCT>->Void});
                    handlerCallArgs.push(macro reject);

                    requestCases.push({
                        values: [methodNameExpr],
                        expr: macro this.$handlerName($a{handlerCallArgs})
                    });
                case TAbstract(_.get() => {name: "NotificationMethod"}, [params]):
                    var paramsCT = params.toComplexType();
                    var sendArgDefs = [];
                    var sendCallArgs = [methodNameExpr];
                    if (params.toString() != "Void") {
                        sendArgDefs.push({name: "params", type: paramsCT});
                        sendCallArgs.push(macro params);
                        handlerArgDefs.push({name: "params", type: paramsCT});
                        handlerCallArgs.push(macro notification.params);
                    } else {
                        sendCallArgs.push(macro null);
                    }

                    fields.push({
                        pos: method.pos,
                        name: "send" + method.name,
                        access: [APublic, AInline],
                        kind: FFun({
                            ret: macro : Void,
                            args: sendArgDefs,
                            expr: macro this.sendNotification($a{sendCallArgs})
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

        var pos = Context.currentPos();
        fields.push({
            pos: pos,
            name: "processRequest",
            access: [AOverride],
            kind: FFun({
                ret: null,
                args: [
                    {name: "request", type: macro : jsonrpc.Types.RequestMessage},
                    {name: "token", type: macro : jsonrpc.Protocol.CancellationToken},
                    {name: "resolve", type: macro : Dynamic->Void},
                    {name: "reject", type: macro : jsonrpc.Types.ResponseError<Dynamic>->Void},
                ],
                expr: {
                    expr: ESwitch(macro request.method, requestCases, macro super.processRequest(request, token, resolve, reject)),
                    pos: pos
                }
            })
        });
        fields.push({
            pos: pos,
            name: "processNotification",
            access: [AOverride],
            kind: FFun({
                ret: null,
                args: [{name: "notification", type: macro : jsonrpc.Types.NotificationMessage}],
                expr: {
                    expr: ESwitch(macro notification.method, notificationCases, null),
                    pos: pos
                }
            })
        });

        return fields;
    }
}

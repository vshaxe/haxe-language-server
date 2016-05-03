package vscodeProtocol;

import haxe.macro.Context;
import haxe.macro.Expr;
using haxe.macro.Tools;

class ProtocolMacro {
    macro static function build():Array<Field> {
        var fields = Context.getBuildFields();

        var requestCases = new Array<Case>();
        var notificationCases = new Array<Case>();

        var ab = switch (Context.getType("ProtocolTypes.MethodName").follow()) {
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
                case TAbstract(_.get() => {name: "Request"}, [params, resultData, errorData]):
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

                    handlerArgDefs.push({name: "reject", type: macro : jsonrpc.Types.ResponseError<Dynamic>->Void});
                    handlerCallArgs.push(macro reject);

                    requestCases.push({
                        values: [methodNameExpr],
                        expr: macro this.$handlerName($a{handlerCallArgs})
                    });
                case TAbstract(_.get() => {name: "Notification"}, [params]):
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
            name: "handleRequest",
            access: [AOverride],
            kind: FFun({
                ret: null,
                args: [
                    {name: "request", type: macro : jsonrpc.Types.RequestMessage},
                    {name: "token", type: macro : jsonrpc.Protocol.CancellationToken},
                    {name: "resolve", type: macro : jsonrpc.Protocol.ResolveHandler},
                    {name: "reject", type: macro : jsonrpc.Protocol.RejectHandler},
                ],
                expr: {
                    expr: ESwitch(macro request.method, requestCases, macro reject(jsonrpc.JsonRpc.error(jsonrpc.ErrorCodes.MethodNotFound, "Method '" + request.method + "' not found"))),
                    pos: pos
                }
            })
        });
        fields.push({
            pos: pos,
            name: "handleNotification",
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

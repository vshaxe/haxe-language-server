package haxeLanguageServer.features;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import haxeLanguageServer.vscodeProtocol.Types;
import haxeLanguageServer.TypeHelper.*;

using StringTools;

class SignatureHelpFeature extends Feature {
    override function init() {
        context.protocol.onSignatureHelp = onSignatureHelp;
    }

    function onSignatureHelp(params:TextDocumentPositionParams, token:CancellationToken, resolve:SignatureHelp->Void, reject:ResponseError<Void>->Void) {
        var doc = context.documents.get(params.textDocument.uri);

        var r = calculateSignaturePosition(doc.content, doc.offsetAt(params.position));
        if (r == null)
            return reject(new ResponseError(0, "Invalid signature position " + params.position));

        var bytePos = doc.offsetToByteOffset(r.pos);
        var args = ["--display", '${doc.fsPath}@$bytePos'];
        var stdin = if (doc.saved) null else doc.content;
        callDisplay(args, stdin, token, function(data) {
            if (token.canceled)
                return;

            data = '<x>$data</x>';
            var xml = try Xml.parse(data).firstElement() catch (_:Dynamic) null;
            if (xml == null) return reject(ResponseError.internalError("Invalid xml data: " + data));

            var signatures = new Array<SignatureInformation>();
            for (el in xml.elements()) {
                var text = el.firstChild().nodeValue.trim();
                var signature:SignatureInformation;
                switch (parseDisplayType(text)) {
                    case DTFunction(args, ret):
                        signature = {
                            label: printFunctionSignature(args, ret),
                            parameters: [for (arg in args) {label: printFunctionArgument(arg)}],

                        }
                    default:
                        signature = {label: text}; // this should not happen
                }
                signatures.push(signature);
            }

            resolve({
                signatures: signatures,
                activeSignature: 0,
                activeParameter: r.arg,
            });
        }, function(error) reject(ResponseError.internalError(error)));
    }

    public static function calculateSignaturePosition(text:String, index:Int):SignaturePosition {
        text = prepareText(text.substring(0, index));

        var parens = 0;
        var braces = 0;
        var brackets = 0;
        var argIndex = 0;

        var i = index - 1;
        while (i > 0) {
            switch (text.fastCodeAt(i)) {
                case c = ("\"".code | "'".code):
                    // just quickly skip strings to the matching boundary character
                    while (i >= 0) {
                        i--;
                        if (text.fastCodeAt(i) == c)
                            break;
                    }

                case ",".code:
                    if (parens == 0 && braces == 0 && brackets == 0)
                        argIndex++; // so far we know we're outside (), [] and {}, so let's try counting commas

                case ")".code:
                    parens++;

                case "}".code:
                    braces++;

                case "]".code:
                    brackets++;

                case "(".code:
                    if (parens > 0) {
                        parens--;
                    } else {
                        var textBefore = text.substring(0, i);
                        if (reEndsWithCall.match(textBefore)) { // looks like a call
                            if (reEndsWithFunctionDef.match(textBefore)) // but maybe a function definition
                                return null;
                            else
                                return { // yay, it's a call!
                                    pos: i + 1,
                                    arg: argIndex
                                };
                        }
                        argIndex = 0; // counted commas somehow appeared in random parens that are not a call
                    }

                case "{".code:
                    if (braces > 0)
                        braces--;
                    else
                        argIndex = 0; // counted commas were inside structure

                case "[".code:
                    if (brackets > 0)
                        brackets--;
                    else
                        argIndex = 0; // counted commas were inside array
            }
            i--;
        }

        return null;
    }

    static var reEndsWithCall = ~/[\w\]\)]\s*$/;
    static var reEndsWithFunctionDef = ~/\Wfunction(?:\s+\w+)?(?:<[\w<>, ]+>)?\s*$/;
    static var reStartsWithString = ~/^"(?:[^"\\]*(?:\\.[^"\\]*)*)"|'(?:[^'\\]*(?:\\.[^'\\]*)*)'/;
    static var reStartsWithRegex = ~/^~\/(?:[^\/\\]*(?:\\.[^\/\\]*)*)\//;

    // clear code of comments, strings and regexes to simplify parsing
    static function prepareText(input:String):String {
        var output = "";
        var inLineComment = false;
        var inBlockComment = false;

        var i = 0, len = input.length;
        while (i < len) {
            if (inLineComment) {
                if (input.fastCodeAt(i) == "\n".code) {
                    inLineComment = false;
                    output += "\n";
                } else {
                    output += " ";
                }
                i++;
            } else if (inBlockComment) {
                if (input.substr(i, 2) == "*/") {
                    inBlockComment = false;
                    output += "  ";
                    i += 2;
                } else {
                    if (input.fastCodeAt(i) == "\n".code)
                        output += "\n";
                    else
                        output += " ";
                    i++;
                }
            } else if (input.substr(i, 2) == "//") {
                inLineComment = true;
                output += "  ";
                i += 2;
            } else if (input.substr(i, 2) == "/*") {
                inBlockComment = true;
                output += "  ";
                i += 2;
            } else if (input.fastCodeAt(i) == "'".code || input.fastCodeAt(i) == "\"".code) {
                if (reStartsWithString.match(input.substring(i))) {
                    output += "\"";
                    var stringLength = reStartsWithString.matched(0).length;
                    for (k in 0...stringLength - 2)
                        output += " ";
                    output += "\"";
                    i += stringLength;
                } else {
                    // non-terminated string, remove it completely
                    while (i < len) {
                        output += " ";
                        i++;
                    }
                }
            } else if (input.fastCodeAt(i) == "~".code) {
                if (reStartsWithRegex.match(input.substring(i))) {
                    output += "~/";
                    var regexLength = reStartsWithRegex.matched(0).length;
                    for (k in 1...regexLength - 2)
                        output += " ";
                    output += "/";
                    i += regexLength;
                } else {
                    // non-terminated regex, remove it completely
                    while (i < len) {
                        output += " ";
                        i++;
                    }
                }
            } else {
                output += input.charAt(i);
                i++;
            }
        }

        return output.toString();
    }
}

private typedef SignaturePosition = {
    var pos:Int;
    var arg:Int;
}

package haxeLanguageServer.features;

import haxeLanguageServer.helper.WorkspaceEditHelper;
import haxeLanguageServer.helper.IdentifierHelper;
import haxeLanguageServer.helper.TypeHelper;
import haxeLanguageServer.features.SignatureHelpFeature.CurrentSignature;
import haxeLanguageServer.tokentree.SyntaxModernizer;

class CodeGenerationFeature {
    final context:Context;
    var currentSignature(get,never):CurrentSignature;

    inline function get_currentSignature() {
        return context.signatureHelp.currentSignature;
    }

    public function new(context:Context) {
        this.context = context;
        context.registerCodeActionContributor(generateAnonymousFunction);
        context.registerCodeActionContributor(generateCaptureVariables);
        #if debug
        context.registerCodeActionContributor(modernizeSyntax);
        #end
    }

    function isSignatureValid(params:CodeActionParams):Bool {
        return currentSignature != null && currentSignature.params.textDocument.uri == params.textDocument.uri;
    }

    function generateAnonymousFunction(params:CodeActionParams):Array<CodeAction> {
        if (!isSignatureValid(params)) return [];

        var help = currentSignature.help;
        var activeParam = help.signatures[help.activeSignature].parameters[help.activeParameter];
        if (activeParam == null) return [];

        var position = currentSignature.params.position;
        var currentType = TypeHelper.parseFunctionArgumentType(activeParam.label);
        switch (currentType) {
            case DTFunction(args, ret):
                var names = IdentifierHelper.guessNames(args);
                for (i in 0...args.length) args[i].name = names[i];

                var generatedCode = TypeHelper.printFunctionDeclaration(args, ret, context.config.codeGeneration.functions.anonymous) + " ";
                return [{
                    title: "Generate anonymous function",
                    edit: WorkspaceEditHelper.create(context, params, [{range: position.toRange(), newText: generatedCode}])
                }];
            case _:
                return [];
        }
    }

    function generateCaptureVariables(params:CodeActionParams):Array<CodeAction> {
        if (!isSignatureValid(params) || currentSignature.help.activeParameter != 0) return [];

        var doc = context.documents.get(params.textDocument.uri);
        var position = currentSignature.params.position;
        var line = doc.lineAt(position.line);
        var textBefore = line.substring(0, position.character);
        var textAfter = line.substr(position.character);

        // ensure we're at a valid position (a "case" without any arguments)
        if (!~/\bcase [a-zA-Z]\w+\s*\($/.match(textBefore) || !textAfter.rtrim().startsWith(")")) return [];

        var activeSignature = currentSignature.help.signatures[currentSignature.help.activeSignature];
        var argNames = [for (arg in activeSignature.parameters) arg.label.split(":")[0]];
        return [{
            title: "Generate capture variables",
            edit: WorkspaceEditHelper.create(context, params, [{range: position.toRange(), newText: argNames.join(", ")}])
        }];
    }

    function modernizeSyntax(params:CodeActionParams):Array<CodeAction> {
        var doc = context.documents.get(params.textDocument.uri);
        try {
            return new SyntaxModernizer(doc).resolve();
        } catch (e:Any) {
            return [];
        }
    }
}

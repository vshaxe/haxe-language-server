package haxeLanguageServer.features;

import languageServerProtocol.Types;
import haxeLanguageServer.helper.TypeHelper;

class CodeGenerationFeature {
    private var context:Context;

    public function new(context:Context) {
        this.context = context;
        context.codeActions.registerContributor(generateAnonymousFunction);
        context.codeActions.registerContributor(extractVariable);
    }

    function generateAnonymousFunction(params:CodeActionParams):Array<Command> {
        var currentSignature = context.signatureHelp.currentSignature;
        if (currentSignature == null || currentSignature.params.textDocument.uri != params.textDocument.uri) return [];

        var help = currentSignature.help;
        var activeParam = help.signatures[help.activeSignature].parameters[help.activeParameter];
        if (activeParam == null) return [];
        
        var position = currentSignature.params.position;
        var currentType = TypeHelper.parseFunctionArgumentType(activeParam.label);
        switch (currentType) {
            case DTFunction(args, ret):
                var generatedCode = TypeHelper.printFunctionDeclaration(args, ret, context.config.codeGeneration.functions.anonymous) + " ";
                return [{
                    title: "Generate anonymous function",
                    command: "haxe.applyFixes",
                    arguments: [params.textDocument.uri, 0, [{range: position.toRange(), newText: generatedCode}]]
                }];
            case _:
                return [];
        }
    }

    function extractVariable(params:CodeActionParams):Array<Command> {
        if (params.range.isEmpty()) return [];
        
        var doc = context.documents.get(params.textDocument.uri);
        var range = params.range;
        var startLine = range.start.line;
        var indent = doc.indentAt(startLine);
        var extraction = doc.getRange(range).replace("$", "\\$");
        var variable = '${indent}var $$ = $extraction;\n';
        var insertRange = {line: startLine, character: 0}.toRange();
        
        return [{
            title: "Extract variable",
            arguments: [params.textDocument.uri, 0, [{range: insertRange, newText: variable}, {range: params.range, newText: "$"}]],
            command: "haxe.applyFixes"
        }];
    }
}

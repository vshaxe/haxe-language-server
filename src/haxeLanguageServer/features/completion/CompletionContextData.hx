package haxeLanguageServer.features.completion;

import haxeLanguageServer.helper.FunctionFormattingConfig;
import haxe.display.JsonModuleTypes;
import haxeLanguageServer.helper.ImportHelper;
import haxeLanguageServer.protocol.helper.DisplayPrinter;
import haxeLanguageServer.protocol.Display.CompletionMode;
using Lambda;

typedef CompletionContextData = {
    var replaceRange:Range;
    var mode:CompletionMode<Dynamic>;
    var doc:TextDocument;
    var indent:String;
    var lineAfter:String;
    var completionPosition:Position;
    var importPosition:Position;
}

class CompletionContextDataHelper {
    public static function createFunctionImportsEdit<T>(data:CompletionContextData, context:Context, type:JsonType<T>, formatting:FunctionFormattingConfig):Array<TextEdit> {
        var importConfig = context.config.codeGeneration.imports;
        if (!importConfig.enableAutoImports) {
            return [];
        }
        var printer = new DisplayPrinter(false, Always);
        var paths = [];
        var signature = type.extractFunctionSignature();
        if (formatting.argumentTypeHints && (!formatting.useArrowSyntax || signature.args.length != 1)) {
            paths = paths.concat(signature.args.map(arg -> arg.t.resolveImports()).flatten().array());
        }
        if (formatting.printReturn(signature)) {
            paths = paths.concat(signature.ret.resolveImports());
        }

        if (paths.length == 0) {
            return [];
        } else {
            return [ImportHelper.createImportsEdit(data.doc, data.importPosition, paths.map(printer.printPath), importConfig.style)];
        }
    }
}

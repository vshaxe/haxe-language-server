package haxeLanguageServer.helper;
import haxeLanguageServer.features.completion.CompletionContextData;

class CompletionContextDataHelper {
    public static function normalizedRange(data : CompletionContextData) : Range {
        return data.replaceRange != null ? data.replaceRange : data.completionPosition.toRange();
    }
}


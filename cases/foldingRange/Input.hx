import haxeLanguageServer.tokentree.FoldingRangeResolver;
import languageServerProtocol.protocol.FoldingRange;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import jsonrpc.CancellationToken;

using StringTools;
using Lambda;

/**
    Doc comment
**/
class Foo {
    /**
     * JavaDoc-style doc comment
     */
    function bar() {
        var someStruct = {
            foo: 0,
            bar: 1
        }

        var emptyStruct = {


        }
    }
}

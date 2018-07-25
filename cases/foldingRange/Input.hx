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

        #if foo
        #end

        #if foo
        
        #end

        #if (haxe_ver >= "4.0.0")
        trace("Haxe 4");
        #end

        #if outer
            #if inner1
            call();
            #elseif (haxe_ver >= "4.0.0")
            call();
            #else
            call();
            #end

            #if inner1
            call();
            #elseif foo
            call();
            call();
            call();
            #error "foo"
            call();
            #else
            call();
            #end
        #end
    }
}

// # region name
    // # region name
    // # endregion

    //# region name
    //# endregion
// # endregion


// region name
// end region


// { region name
// } endregion
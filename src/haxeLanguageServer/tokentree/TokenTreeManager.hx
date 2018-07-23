package haxeLanguageServer.tokentree;

import byte.ByteData;
import haxe.io.Bytes;
import tokentree.TokenStream;
import tokentree.TokenTreeBuilder;
import tokentree.TokenTree;
import haxeparser.HaxeLexer;
import haxeparser.Data.Token;

class TokenTreeManager {
    public static function create(content:String):TokenTreeManager {
        var bytes = Bytes.ofString(content);
        var tokens = createTokens(bytes);
        var tree = createTokenTree(bytes, tokens);
        return new TokenTreeManager(bytes, tokens, tree);
    }

    static function createTokens(bytes:Bytes):Array<Token> {
        try {
            var tokens = [];
            var lexer = new HaxeLexer(ByteData.ofBytes(bytes));
            var t:Token = lexer.token(haxeparser.HaxeLexer.tok);
            while (t.tok != Eof) {
                tokens.push(t);
                t = lexer.token(haxeparser.HaxeLexer.tok);
            }
            return tokens;
        } catch (e:Any) {
            throw 'failed to create tokens: $e';
        }
    }

    static function createTokenTree(bytes:Bytes, tokens:Array<Token>):TokenTree {
        try {
            TokenStream.MODE = RELAXED;
            return TokenTreeBuilder.buildTokenTree(tokens, ByteData.ofBytes(bytes));
        } catch (e:Any) {
            throw 'failed to create token tree: $e';
        }
    }

    public final bytes:Bytes;
    public final list:Array<Token>;
    public final tree:TokenTree;

    function new(bytes:Bytes, list:Array<Token>, tree:TokenTree) {
        this.bytes = bytes;
        this.list = list;
        this.tree = tree;
    }
}

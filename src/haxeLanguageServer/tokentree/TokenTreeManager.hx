package haxeLanguageServer.tokentree;

import js.node.Buffer;
import byte.ByteData;
import haxe.io.Bytes;
import tokentree.TokenStream;
import tokentree.TokenTreeBuilder;
import tokentree.TokenTree;
import haxeparser.HaxeLexer;
import haxeparser.Data.Token;
import haxe.macro.Expr.Position;

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

	var tokenCharacterRanges:Null<Map<Int, Position>>;

	function new(bytes:Bytes, list:Array<Token>, tree:TokenTree) {
		this.bytes = bytes;
		this.list = list;
		this.tree = tree;
	}

	/**
		Gets the character position of a token.
	**/
	public function getPos(tokenTree:TokenTree):Null<Position> {
		inline createTokenCharacterRanges();
		return if (tokenCharacterRanges[tokenTree.index] == null) {
			tokenTree.pos;
		} else {
			tokenCharacterRanges[tokenTree.index];
		}
	}

	/**
		Gets the character position of a subtree.
		Copy of `TokenTree.getPos()`.
	**/
	public function getTreePos(tokenTree:TokenTree):Null<Position> {
		var pos = getPos(tokenTree);
		if (pos == null || tokenTree.children == null || tokenTree.children.length <= 0)
			return pos;

		var fullPos:Position = {file: pos.file, min: pos.min, max: pos.max};
		for (child in tokenTree.children) {
			var childPos = getTreePos(child);
			if (childPos == null)
				continue;

			if (childPos.min < fullPos.min)
				fullPos.min = childPos.min;
			if (childPos.max > fullPos.max)
				fullPos.max = childPos.max;
		}
		return fullPos;
	}

	function createTokenCharacterRanges() {
		if (tokenCharacterRanges != null) {
			return;
		}
		tokenCharacterRanges = new Map();
		var offset = 0;
		for (i in 0...list.length) {
			var token = list[i];
			offset += switch (token.tok) {
				// these should be the only places where Unicode characters can appear in Haxe
				case Const(CString(s)), Const(CRegexp(s, _)), Comment(s), CommentLine(s):
					s.length - Buffer.byteLength(s);
				case _:
					0;
			}
			if (offset != 0) {
				tokenCharacterRanges[i] = {
					file: token.pos.file,
					min: token.pos.min + offset,
					max: token.pos.max + offset
				};
			}
		}
	}
}

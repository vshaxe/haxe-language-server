package haxeLanguageServer.features.haxe.documentSymbols;

import haxe.display.Display.DisplayModuleTypeKind;
import languageServerProtocol.Types.DocumentSymbol;

/** (_not_ a video game level, simn) **/
enum SymbolLevel {
	Root;
	Type(kind:DisplayModuleTypeKind);
	Field;
	Expression;
}

abstract SymbolStack(Array<{level:SymbolLevel, symbol:DocumentSymbol}>) {
	public var depth(get, set):Int;

	inline function get_depth()
		return this.length - 1;

	function set_depth(newDepth:Int) {
		if (newDepth > depth) {
			// only accounts for increases of 1
			if (this[newDepth] == null) {
				this[newDepth] = this[newDepth - 1];
			}
		} else if (newDepth < depth) {
			while (depth > newDepth) {
				this.pop();
			}
		}
		return depth;
	}

	public var level(get, never):SymbolLevel;

	inline function get_level()
		return this[depth].level;

	public var root(get, never):DocumentSymbol;

	inline function get_root()
		return this[0].symbol;

	public function new() {
		@:nullSafety(Off)
		this = [
			{
				level: Root,
				symbol: {
					name: "root",
					kind: Module,
					range: null,
					selectionRange: null,
					children: []
				}
			}
		];
	}

	public function addSymbol(level:SymbolLevel, symbol:DocumentSymbol, opensScope:Bool) {
		final parentSymbol = this[depth].symbol;
		if (parentSymbol.children == null) {
			parentSymbol.children = [];
		}
		parentSymbol.children.push(symbol);

		if (opensScope) {
			this[depth + 1] = {level: level, symbol: symbol};
		}
	}

	public function getParentTypeKind():Null<DisplayModuleTypeKind> {
		var i = depth;
		while (i-- > 0) {
			switch this[i].level {
				case Type(kind):
					return kind;
				case _:
			}
		}
		return null;
	}
}

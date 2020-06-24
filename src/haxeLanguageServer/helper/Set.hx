package haxeLanguageServer.helper;

// meh
abstract Set<T:{}>(Map<T, Bool>) {
	public inline function new() {
		this = new Map();
	}

	public inline function add(item:T) {
		this[item] = true;
	}

	public inline function remove(item:T) {
		this[item] = false;
	}

	public inline function has(item:T):Bool {
		return this[item] == true;
	}
}

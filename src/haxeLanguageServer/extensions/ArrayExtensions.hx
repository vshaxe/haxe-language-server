package haxeLanguageServer.extensions;

using Lambda;

inline function occurrences<T>(a:Array<T>, element:T):Int {
	return a.count(e -> e == element);
}

function equals<T>(a1:Array<T>, a2:Array<T>):Bool {
	if (a1 == null && a2 == null)
		return true;
	if (a1 == null && a2 != null)
		return false;
	if (a1 != null && a2 == null)
		return false;
	if (a1.length != a2.length)
		return false;
	for (i in 0...a1.length)
		if (a1[i] != a2[i])
			return false;
	return true;
}

function filterDuplicates<T>(array:Array<T>, filter:(a:T, b:T) -> Bool):Array<T> {
	final unique:Array<T> = [];
	for (element in array) {
		var present = false;
		for (unique in unique)
			if (filter(unique, element))
				present = true;
		if (!present)
			unique.push(element);
	}
	return unique;
}

inline function unique<T>(array:Array<T>):Array<T> {
	return filterDuplicates(array, (e1, e2) -> e1 == e2);
}

package haxeLanguageServer.helper;

class ArrayHelper {
	public static function occurrences<T>(a:Array<T>, element:T):Int {
		var occurrences = 0;
		for (e in a)
			if (e == element)
				occurrences++;
		return occurrences;
	}

	public static function equals<T>(a1:Array<T>, a2:Array<T>):Bool {
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

	public static function filterDuplicates<T>(array:Array<T>, filter:(a:T, b:T) -> Bool):Array<T> {
		var unique:Array<T> = [];
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

	public static inline function unique<T>(array:Array<T>):Array<T> {
		return filterDuplicates(array, (e1, e2) -> e1 == e2);
	}
}

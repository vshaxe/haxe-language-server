package haxeLanguageServer.protocol;

import haxe.display.JsonModuleTypes.JsonType;
import haxeLanguageServer.protocol.DisplayPrinter.PathPrinting;

enum abstract DotPath(String) {
	final Bool = "StdTypes.Bool";
	final Int = "StdTypes.Int";
	final UInt = "UInt";
	final Float = "StdTypes.Float";
	final String = "String";
	final EitherType = "haxe.extern.EitherType";
	final Array = "Array";
	final Map = "haxe.ds.Map";
	final ReadOnlyArray = "haxe.ds.ReadOnlyArray";
	final EReg = "EReg";
	function new(dotPath) {
		this = dotPath;
	}
}

function getDotPath<T>(type:JsonType<T>):Null<DotPath> {
	var path = type.getTypePath();
	if (path == null) {
		return null;
	}
	return @:privateAccess new DotPath(new DisplayPrinter(PathPrinting.Always).printPath(path.path));
}

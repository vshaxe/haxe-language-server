package haxeLanguageServer.protocol;

import haxe.display.JsonModuleTypes.JsonType;
import haxe.display.JsonModuleTypes.JsonTypePath;
import haxeLanguageServer.protocol.DisplayPrinter.PathPrinting;

enum abstract DotPath(String) {
	final Void = "StdTypes.Void";
	final Bool = "StdTypes.Bool";
	final Int = "StdTypes.Int";
	final Float = "StdTypes.Float";
	final Null = "StdTypes.Null";
	final UInt;
	final String;
	final EitherType = "haxe.extern.EitherType";
	final Array;
	final Map = "haxe.ds.Map";
	final ReadOnlyArray = "haxe.ds.ReadOnlyArray";
	final EReg;
	final Dynamic;
	function new(dotPath) {
		this = dotPath;
	}
}

function getDotPath<T>(type:JsonType<T>):Null<DotPath> {
	final path = type.getTypePath();
	if (path == null) {
		return null;
	}
	return getDotPath2(path.path);
}

function getDotPath2<T>(path:JsonTypePath):DotPath {
	return @:privateAccess new DotPath(new DisplayPrinter(PathPrinting.Always).printPath(path));
}

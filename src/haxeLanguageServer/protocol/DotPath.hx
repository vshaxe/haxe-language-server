package haxeLanguageServer.protocol;

import haxe.display.JsonModuleTypes.JsonType;
import haxe.display.JsonModuleTypes.JsonTypePath;
import haxeLanguageServer.protocol.DisplayPrinter.PathPrinting;

enum abstract DotPath(String) {
	final Std_Void = "StdTypes.Void";
	final Std_Bool = "StdTypes.Bool";
	final Std_Int = "StdTypes.Int";
	final Std_Float = "StdTypes.Float";
	final Std_Null = "StdTypes.Null";
	final Std_UInt = "UInt";
	final Std_String = "String";
	final Std_Array = "Array";
	final Std_EReg = "EReg";
	final Std_Dynamic = "Dynamic";
	final Haxe_Extern_EitherType = "haxe.extern.EitherType";
	final Haxe_Ds_Map = "haxe.ds.Map";
	final Haxe_Ds_ReadOnlyArray = "haxe.ds.ReadOnlyArray";
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

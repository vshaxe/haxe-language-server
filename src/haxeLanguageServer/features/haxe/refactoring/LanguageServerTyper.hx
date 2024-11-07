package haxeLanguageServer.features.haxe.refactoring;

import haxe.display.Display.DisplayMethods;
import haxe.display.Display.HoverDisplayItemOccurence;
import haxeLanguageServer.protocol.DotPath.getDotPath;
import js.lib.Promise;
import refactor.ITypeList;
import refactor.ITyper;
import refactor.rename.RenameHelper.TypeHintType;

using Lambda;
using haxeLanguageServer.helper.PathHelper;

class LanguageServerTyper implements ITyper {
	final context:Context;

	public var typeList:Null<ITypeList>;

	public function new(context:Context) {
		this.context = context;
	}

	public function resolveType(filePath:String, pos:Int):Promise<Null<TypeHintType>> {
		final params = {
			file: new FsPath(filePath),
			offset: pos,
			wasAutoTriggered: true
		};
		#if debug
		trace('[rename] requesting type info for $filePath@$pos');
		#end
		var promise = new Promise(function(resolve:(value:Null<TypeHintType>) -> Void, reject) {
			context.callHaxeMethod(DisplayMethods.Hover, params, null, function(hover) {
				if (hover == null) {
					#if debug
					trace('[rename] received no type info for $filePath@$pos');
					#end
					resolve(null);
				} else {
					resolve(buildTypeHint(hover, '$filePath@$pos'));
				}
				return null;
			}, reject.handler());
		});
		return promise;
	}

	function buildTypeHint<T>(item:HoverDisplayItemOccurence<T>, location:String):Null<TypeHintType> {
		if (typeList == null) {
			return null;
		}
		var reg = ~/Class<(.*)>/;

		var type = item?.item?.type;
		if (type == null) {
			return null;
		}
		var path = type?.args?.path;
		if (path == null) {
			return null;
		}
		if (path.moduleName == "StdTypes" && path.typeName == "Null") {
			var params = type?.args?.params;
			if (params == null) {
				return null;
			}
			type = params[0];
			if (type == null) {
				return null;
			}
			path = type?.args?.path;
			if (path == null) {
				return null;
			}
		}
		if (reg.match(path.typeName)) {
			var fullPath = reg.matched(1);
			var parts = fullPath.split(".");
			if (parts.length <= 0) {
				return null;
			}
			@:nullSafety(Off)
			path.typeName = parts.pop();
			path.pack = parts;
		}
		var fullPath = '${getDotPath(type)}';
		#if debug
		trace('[rename] received type $fullPath for $location');
		#end
		return typeList.makeTypeHintType(fullPath);
	}
}

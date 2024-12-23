package haxeLanguageServer.features.haxe.refactoring;

import haxe.display.Display.DisplayMethods;
import haxe.display.Display.HoverDisplayItemOccurence;
import haxe.display.JsonModuleTypes.JsonType;
import haxeLanguageServer.protocol.DisplayPrinter;
import js.lib.Promise;
import refactor.typing.ITypeList;
import refactor.typing.ITyper;
import refactor.typing.TypeHintType;

using Lambda;
using haxeLanguageServer.helper.PathHelper;

class LanguageServerTyper implements ITyper {
	final context:Context;
	final printer:DisplayPrinter;
	final fullPrinter:DisplayPrinter;

	public var typeList:Null<ITypeList>;

	public function new(context:Context) {
		this.context = context;
		printer = new DisplayPrinter();
		fullPrinter = new DisplayPrinter(Always);
	}

	public function resolveType(filePath:String, pos:Int):Promise<Null<TypeHintType>> {
		final params = {
			file: new FsPath(filePath),
			offset: pos,
			wasAutoTriggered: true
		};
		#if debug
		trace('[refactor] requesting type info for $filePath@$pos');
		#end
		var promise = new Promise(function(resolve:(value:Null<TypeHintType>) -> Void, reject) {
			context.callHaxeMethod(DisplayMethods.Hover, params, null, function(hover) {
				if (hover == null) {
					#if debug
					trace('[refactor] received no type info for $filePath@$pos');
					#end
					resolve(null);
				} else {
					final typeHint:Null<TypeHintType> = buildTypeHint(hover, '$filePath@$pos');
					#if debug
					trace('[refactor] received type info for $filePath@$pos: ${refactor.PrintHelper.typeHintToString(typeHint)}');
					#end
					resolve(typeHint);
				}
				return null;
			}, reject.handler());
		});
		return promise;
	}

	function buildType<T>(jsonType:JsonType<T>):Null<TypeHintType> {
		switch (jsonType.kind) {
			case TMono:
				return UnknownType("?");
			case TInst | TEnum | TType | TAbstract:
				final path = jsonType.args;
				final name = printer.printPath(path.path);
				var fullPath = fullPrinter.printPath(path.path);
				final typeName = path.path?.typeName;

				if (typeName != null) {
					if (typeName.startsWith("Abstract<")) {
						fullPath = typeName.substring(9, typeName.length - 1);
					}
					if (typeName.startsWith("Class<")) {
						fullPath = typeName.substring(6, typeName.length - 1);
					}
				}
				final type = typeList?.getType(fullPath);
				final params:Array<TypeHintType> = [];
				if (path.params.length > 0) {
					for (param in path.params) {
						final paramType = buildType(param);
						if (paramType == null) {
							continue;
						}
						params.push(paramType);
					}
				}
				if (type == null) {
					return LibType(name, fullPath, params);
				}
				return ClasspathType(type, params);
			case TDynamic:
				final path = jsonType.args;
				if (path == null) {
					return LibType("Dynamic", "Dynamic", []);
				}
				final paramType = buildType(path);
				if (paramType == null) {
					return LibType("Dynamic", "Dynamic", []);
				}
				return LibType("Dynamic", "Dynamic", [paramType]);
			case TAnonymous:
				final path = jsonType.args;
				final fields:Array<TypeHintType> = [];
				for (field in path.fields) {
					final fieldType = buildType(field.type);
					if (fieldType != null) {
						fields.push(NamedType(field.name, fieldType));
					}
				}
				return StructType(fields);
			case TFun:
				final path = jsonType.args;
				final args:Array<TypeHintType> = [];
				for (arg in path.args) {
					final argType = buildType(arg.t);
					if (argType == null) {
						continue;
					}
					args.push(argType);
				}
				final retVal = buildType(path.ret);
				return FunctionType(args, retVal);
		}
		return null;
	}

	function buildTypeHint<T>(item:HoverDisplayItemOccurence<T>, location:String):Null<TypeHintType> {
		if (typeList == null) {
			return null;
		}

		var type = item?.item?.type;
		if (type == null) {
			return null;
		}
		return buildType(type);
	}
}

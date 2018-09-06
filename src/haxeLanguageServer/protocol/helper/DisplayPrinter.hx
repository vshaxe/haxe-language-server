package haxeLanguageServer.protocol.helper;

import haxe.ds.Option;
import haxe.display.JsonModuleTypes;
import haxeLanguageServer.helper.IdentifierHelper;
import haxeLanguageServer.helper.FunctionFormattingConfig;
import haxeLanguageServer.protocol.Display;

using Lambda;

enum PathPrinting {
	/**
		Always print the full dot path for types.
	**/
	Always;

	/**
		Always only print the unqualified type name.
	**/
	Never;

	/**
		Only print the full dot path when unimported or shadowed (so it's always qualified).
	**/
	Qualified;

	/**
		Only print the full dot path for shadowed types (usually used when generating auto-imports).
	**/
	Shadowed;
}

class DisplayPrinter {
	final wrap:Bool;
	final pathPrinting:PathPrinting;
	final functionFormatting:FunctionFormattingConfig;
	var indent = "";

	public function new(wrap:Bool = false, ?pathPrinting:PathPrinting, ?functionFormatting:FunctionFormattingConfig) {
		this.wrap = wrap;
		this.pathPrinting = pathPrinting;
		if (this.pathPrinting == null) {
			this.pathPrinting = Qualified;
		}
		this.functionFormatting = functionFormatting;
		if (this.functionFormatting == null) {
			this.functionFormatting = {
				useArrowSyntax: true,
				returnTypeHint: NonVoid,
				argumentTypeHints: true
			}
		}
	}

	public function printPath(path:JsonTypePath) {
		var qualified = switch (pathPrinting) {
			case Always: true;
			case Never: false;
			case Qualified: path.importStatus != Imported;
			case Shadowed: path.importStatus == Shadowed;
		}
		var isSubType = path.moduleName != path.typeName;
		var isToplevelType = path.pack.length == 0 && !isSubType;
		if (isToplevelType && path.importStatus == Shadowed) {
			path.pack.push("std");
		}
		return if (qualified) {
			var printedPath = path.moduleName + (if (isSubType) "." + path.typeName else "");
			if (path.pack.length > 0) {
				printedPath = path.pack.join(".") + "." + printedPath;
			}
			printedPath;
		} else {
			path.typeName;
		}
	}

	public function printPathWithParams(path:JsonTypePathWithParams) {
		var s = printPath(path.path);
		if (path.params.length == 0) {
			return s;
		} else {
			var sparams = path.params.map(printType).join(", ");
			return '$s<$sparams>';
		}
	}

	public function printType<T>(t:JsonType<T>) {
		return switch (t.kind) {
			case TMono: "?";
			case TInst | TEnum | TType | TAbstract: printPathWithParams(t.args);
			case TDynamic:
				if (t.args == null) {
					"Dynamic";
				} else {
					var s = printTypeRec(t.args);
					'Dynamic<$s>';
				}
			case TAnonymous:
				var fields = t.args.fields;
				var s = [for (field in fields) '${field.name}:${printTypeRec(field.type)}'].join(", ");
				'{$s}';
			case TFun:
				var hasNamed = false;
				function printFunctionArgument(arg:JsonFunctionArgument) {
					if (arg.name != "") {
						hasNamed = true;
					}
					return this.printFunctionArgument(arg);
				}
				var args = t.args.args.map(printFunctionArgument);
				var r = printTypeRec(t.args.ret);
				switch (args.length) {
					case 0: '() -> $r';
					case 1 if (hasNamed): '(${args[0]}) -> $r';
					case 1: '${args[0]} -> $r';
					case _:
						var busy = args.fold((args, i) -> i + args.length, 0);
						if (busy < 50 || !wrap) {
							var s = args.join(", ");
							'($s) -> $r';
						} else {
							var s = args.join(',\n $indent');
							'($s)\n$indent-> $r';
						}
				}
		}
	}

	function printTypeRec<T>(t:JsonType<T>) {
		var old = indent;
		indent += "  ";
		var t = printType(t);
		indent = old;
		return t;
	}

	public function printFunctionArgument<T>(arg:JsonFunctionArgument) {
		var nullRemoval = arg.t.removeNulls();
		var concreteType = if (functionFormatting.explicitNull) arg.t else nullRemoval.type;
		var optional = nullRemoval.optional;

		var argument = (if (optional) "?" else "") + arg.name;
		if (functionFormatting.argumentTypeHints && (concreteType.kind != TMono || arg.name == "")) {
			argument += (arg.name == "" ? "" : ":") + printTypeRec(concreteType);
		}
		if (arg.value != null) {
			argument += " = " + arg.value.string;
		}
		return argument;
	}

	public function printCallArguments<T>(signature:JsonFunctionSignature, printFunctionArgument:JsonFunctionArgument->String) {
		return "(" + signature.args.map(printFunctionArgument).join(", ") + ")";
	}

	public function printTypeParameters(params:JsonTypeParameters) {
		return if (params.length == 0) {
			"";
		} else {
			"<" + params.map(param -> {
				var s = param.name;
				if (param.constraints.length > 0) {
					s += ":" + param.constraints.map(constraint -> printTypeRec(constraint)).join(" & ");
				}
				s;
			}).join(", ") + ">";
		}
	}

	function printReturn(signature:JsonFunctionSignature) {
		if (signature.ret.kind == TMono) {
			return "";
		}
		return if (functionFormatting.printReturn(signature)) {
			":" + printTypeRec(signature.ret);
		} else {
			"";
		}
	}

	public function printEmptyFunctionDefinition<T>(name:String, signature:JsonFunctionSignature, ?params:JsonTypeParameters) {
		var printedParams = if (params == null) "" else printTypeParameters(params);
		return "function " + name + printedParams + printCallArguments(signature, printFunctionArgument) + printReturn(signature);
	}

	public function printOverrideDefinition<T>(field:JsonClassField, concreteType:JsonType<T>, indent:String, snippets:Bool) {
		var access = if (field.isPublic) "public " else "private ";
		if (field.isPublic && !functionFormatting.explicitPublic) {
			access = "";
		}
		if (!field.isPublic && !functionFormatting.explicitPrivate) {
			access = "";
		}
		var signature = concreteType.extractFunctionSignature();
		var returnKeyword = if (signature.ret.isVoid()) "" else "return ";
		var arguments = printCallArguments(signature, arg -> arg.name);
		var lineBreak = if (functionFormatting.placeOpenBraceOnNewLine) "\n" else " ";

		var definition = access + printEmptyFunctionDefinition(field.name, signature, field.params) + '$lineBreak{\n${indent}';
		var superCall = '${returnKeyword}super.${field.name}$arguments;';
		var end = '\n}';
		return if (snippets) {
			definition + '$${1:$superCall}$0$end';
		} else {
			definition + superCall + end;
		}
	}

	static final castRegex = ~/^(cast )+/;

	public function printClassFieldDefinition<T0, T1, T2>(occurrence:ClassFieldOccurrence<T0>, concreteType:JsonType<T1>, isEnumAbstractField:Bool) {
		var field = occurrence.field;
		switch (concreteType.kind) {
			case TMono:
				concreteType = field.type;
			case _:
		}
		var type = printType(concreteType);
		var name = field.name;
		var kind:JsonFieldKind<T2> = field.kind;
		var access = if (field.isPublic) "public " else "private ";
		var staticKeyword = if (field.scope == Static) "static " else "";
		return switch (kind.kind) {
			case FVar:
				var inlineKeyword = if (kind.args.write.kind == AccInline) "inline " else "";
				var keyword = if (kind.args.write.kind == AccCtor || field.isFinalField()) "final" else "var";
				var read = printAccessor(kind.args.read, true);
				var write = printAccessor(kind.args.write, false);
				var accessors = if ((read != null && write != null) && (read != "default" || write != "default")) '($read, $write)' else "";
				// structure fields get some special treatment
				if (occurrence.origin.isStructure()) {
					access = "";
					if (field.meta.hasMeta(Optional)) {
						name = "?" + name;
					}
				} else if (isEnumAbstractField) {
					access = "";
					staticKeyword = "";
				}
				if (keyword == "final") {
					accessors = "";
				}
				var definition = '$access$staticKeyword$keyword $inlineKeyword$name$accessors:$type';
				if (field.expr != null) {
					var expr = castRegex.replace(field.expr.string, "");
					definition += " = " + expr;
				}
				definition;
			case FMethod:
				var methodKind = switch (kind.args) {
					case MethNormal: "";
					case MethInline: "inline ";
					case MethDynamic: "dynamic ";
					case MethMacro: "macro ";
				}
				var finalKeyword = if (field.isFinalField()) "final " else "";
				var definition = printEmptyFunctionDefinition(field.name, concreteType.extractFunctionSignature(), field.params);
				'$access$staticKeyword$finalKeyword$methodKind$definition';
		};
	}

	public function printAccessor<T>(access:JsonVarAccess<T>, isRead:Bool) {
		return switch (access.kind) {
			case AccNormal: "default";
			case AccNo: "null";
			case AccNever: "never";
			case AccResolve: null;
			case AccCall: if (isRead) "get" else "set";
			case AccInline: null;
			case AccRequire: null;
			case AccCtor: null;
		}
	}

	public function printLocalDefinition<T1, T2>(local:DisplayLocal<T1>, concreteType:JsonType<T2>) {
		return switch (local.origin) {
			case LocalFunction:
				var inlineKeyword = if (local.isInline) "inline " else "";
				inlineKeyword + printEmptyFunctionDefinition(local.name, concreteType.extractFunctionSignature(), if (local.extra == null) null else local.extra
					.params);
			case other:
				var keyword = "var ";
				var name = local.name;
				if (other == Argument) {
					keyword = "";
					if (concreteType.removeNulls().optional) {
						name = "?" + name;
					}
				}
				'$keyword$name:${printType(concreteType)}';
		}
	}

	/**
		Prints a type declaration in the form of `extern interface ArrayAccess<T>`.
		(`modifiers... keyword Name<Params>`)
	**/
	public function printEmptyTypeDefinition(type:DisplayModuleType):String {
		var components = [];
		if (type.isPrivate)
			components.push("private");
		if (type.isFinalType())
			components.push("final");
		if (type.isExtern)
			components.push("extern");
		components.push(switch (type.kind) {
			case Class: "class";
			case Interface: "interface";
			case Enum: "enum";
			case Abstract: "abstract";
			case EnumAbstract: "enum abstract";
			case TypeAlias | Struct: "typedef";
		});
		var typeName = type.path.typeName;
		if (type.params.length > 0) {
			typeName += "<" + type.params.map(param -> param.name).join(", ") + ">";
		}
		components.push(typeName);
		return components.join(" ");
	}

	public function printClassFieldOrigin<T>(origin:ClassFieldOrigin<T>, kind:DisplayItemKind<Dynamic>, quote:String = ""):Option<String> {
		if (kind == EnumAbstractField || origin.kind == cast Unknown) {
			return None;
		}
		if (origin.args == null && origin.kind != cast BuiltIn) {
			return None;
		}
		var q = quote;
		return Some("from " + switch (origin.kind) {
			case Self:
				'$q${origin.args.name}$q';
			case Parent:
				'parent type $q${origin.args.name}$q';
			case StaticExtension:
				'$q${origin.args.name}$q (static extension method)';
			case StaticImport:
				'$q${origin.args.name}$q (statically imported)';
			case AnonymousStructure:
				'anonymous structure';
			case BuiltIn:
				'compiler (built-in)';
			case Unknown:
				''; // already handled
		});
	}

	public function printEnumFieldOrigin<T>(origin:EnumFieldOrigin<T>, quote:String = ""):Option<String> {
		if (origin.args == null) {
			return None;
		}
		return Some('from ' + switch (origin.kind) {
			case Self:
				'$quote${origin.args.name}$quote';
			case StaticImport:
				'$quote${origin.args.name}$quote (statically imported)';
		});
	}

	public function printLocalOrigin(origin:LocalOrigin):String {
		return switch (origin) {
			case LocalVariable: "local variable";
			case Argument: "argument";
			case ForVariable: "for variable";
			case PatternVariable: "pattern variable";
			case CatchVariable: "catch variable";
			case LocalFunction: "local function";
		}
	}

	public inline function printEnumFieldDefinition<T>(field:JsonEnumField, concreteType:JsonType<T>) {
		return printEnumField(field, concreteType, false, true);
	}

	public function printEnumField<T>(field:JsonEnumField, concreteType:JsonType<T>, snippets:Bool, typeHints:Bool) {
		return switch (concreteType.kind) {
			case TEnum: field.name;
			case TFun:
				var signature:JsonFunctionSignature = concreteType.args;
				var text = '${field.name}(';
				for (i in 0...signature.args.length) {
					var arg = signature.args[i];
					text += if (snippets) {
						'$${${i+1}:${arg.name}}';
					} else {
						arg.name;
					}

					if (typeHints) {
						text += ":" + printTypeRec(arg.t);
					}

					if (i < signature.args.length - 1) {
						text += ", ";
					}
				}
				text + ")";
			case _: "";
		}
	}

	public function printAnonymousFunctionDefinition(signature:JsonFunctionSignature) {
		var args = signature.args.map(arg -> {
			name: if (arg.name == "") null else arg.name,
			opt: arg.opt,
			type: new DisplayPrinter(PathPrinting.Never).printTypeRec(arg.t)
		});
		var names = IdentifierHelper.guessNames(args);
		var printedArgs = [];
		var singleArgument = args.length == 1;
		if (singleArgument && functionFormatting.useArrowSyntax) {
			printedArgs = [names[0]];
		} else {
			for (i in 0...args.length) {
				printedArgs.push(printFunctionArgument({
					t: signature.args[i].t,
					opt: args[i].opt,
					name: names[i]
				}));
			}
		}
		var printedArguments = printedArgs.join(", ");
		if (functionFormatting.useArrowSyntax) {
			if (!singleArgument) {
				printedArguments = '($printedArguments)';
			}
			return printedArguments + " -> ";
		} else {
			return "function(" + printedArguments + ")" + printReturn(signature) + " ";
		}
	}

	public function printObjectLiteral(anon:JsonAnon, singleLine:Bool, onlyRequiredFields:Bool, snippets:Bool) {
		var printedFields = [];
		for (i in 0...anon.fields.length) {
			var field = anon.fields[i];
			var name = field.name;
			var printedField = name + ': ';
			if (!singleLine) {
				printedField = "\t" + printedField;
			}
			printedField += if (snippets) {
				'$${${i+1}:$name}';
			} else {
				name;
			}
			if (!onlyRequiredFields || !field.meta.hasMeta(Optional)) {
				printedFields.push(printedField);
			}
		}
		if (printedFields.length == 0) {
			return "{}";
		}
		return if (singleLine) {
			'{${printedFields.join(", ")}}';
		} else {
			'{\n${printedFields.join(",\n")}\n}';
		}
	}

	public function printSwitchOnEnum(subject:String, e:JsonEnum, snippets:Bool) {
		var fields = e.constructors.map(field -> printEnumField(field, field.type, false, false));
		return printSwitch(subject, fields, snippets);
	}

	public function printSwitchOnEnumAbstract(subject:String, a:JsonAbstract, snippets:Bool) {
		var fields = a.impl.statics.filter(Helper.isEnumAbstractField).map(field -> field.name);
		return printSwitch(subject, fields, snippets);
	}

	function printSwitch(subject:String, fields:Array<String>, snippets:Bool) {
		for (i in 0...fields.length) {
			var field = fields[i];
			field = '\tcase $field:';
			if (snippets) {
				field += "$" + (i + 1);
			}
			fields[i] = field;
		}
		return 'switch ($subject) {\n${fields.join("\n")}\n}';
	}
}

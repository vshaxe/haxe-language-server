package haxeLanguageServer.protocol;

import haxe.display.Display;
import haxe.display.JsonModuleTypes;
import haxeLanguageServer.Configuration.FunctionFormattingConfig;
import haxeLanguageServer.helper.IdentifierHelper;

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
	var qualifiedPaths:Null<Array<String>>;

	public function new(wrap:Bool = false, pathPrinting:PathPrinting = Qualified, ?functionFormatting:FunctionFormattingConfig) {
		this.wrap = wrap;
		this.pathPrinting = pathPrinting;
		this.functionFormatting = if (functionFormatting == null) {
			{
				useArrowSyntax: true,
				returnTypeHint: NonVoid,
				argumentTypeHints: true,
				placeOpenBraceOnNewLine: false,
				explicitPublic: false,
				explicitPrivate: false,
				explicitNull: false
			}
		} else {
			functionFormatting;
		}
	}

	public function collectQualifiedPaths() {
		var previous = qualifiedPaths;
		var current = qualifiedPaths = [];
		return function():Array<String> {
			qualifiedPaths = previous;
			return current;
		}
	}

	public function printPath(path:JsonTypePath) {
		final qualified = switch pathPrinting {
			case Always: true;
			case Never: false;
			case Qualified: path.importStatus != Imported;
			case Shadowed: path.importStatus == Shadowed;
		}
		final isSubType = path.moduleName != path.typeName;
		final isToplevelType = path.pack.length == 0 && !isSubType;
		if (isToplevelType && path.importStatus == Shadowed) {
			path.pack.push("std");
		}
		function printFullPath() {
			var printedPath = path.moduleName + (if (isSubType) "." + path.typeName else "");
			if (path.pack.length > 0) {
				printedPath = path.pack.join(".") + "." + printedPath;
			}
			return printedPath;
		}
		return if (qualified) {
			printFullPath();
		} else {
			if (path.importStatus == Unimported && qualifiedPaths != null) {
				qualifiedPaths.push(printFullPath());
			}
			path.typeName;
		}
	}

	public function printPathWithParams(path:JsonTypePathWithParams) {
		final s = printPath(path.path);
		if (path.params.length == 0) {
			return s;
		} else {
			var sparams = path.params.map(printType).join(", ");
			return '$s<$sparams>';
		}
	}

	public function printType<T>(t:JsonType<T>) {
		return switch t.kind {
			case TMono: "?";
			case TInst | TEnum | TType | TAbstract: printPathWithParams(t.args);
			case TDynamic:
				if (t.args == null) {
					"Dynamic";
				} else {
					final s = printTypeRec(t.args);
					'Dynamic<$s>';
				}
			case TAnonymous:
				final fields = t.args.fields;
				final s = [
					for (field in fields) {
						var prefix = if (field.meta.hasMeta(Optional)) "?" else "";
						'$prefix${field.name}:${printTypeRec(field.type)}';
					}
				].join(", ");
				'{$s}';
			case TFun:
				var hasNamed = false;
				function printFunctionArgument(arg:JsonFunctionArgument) {
					if (arg.name != "") {
						hasNamed = true;
					}
					return this.printFunctionArgument(arg);
				}
				final args = t.args.args.map(printFunctionArgument);
				final r = printTypeRec(t.args.ret);
				switch args.length {
					case 0: '() -> $r';
					case 1 if (hasNamed): '(${args[0]}) -> $r';
					case 1: '${args[0]} -> $r';
					case _:
						final busy = args.fold((args, i) -> i + args.length, 0);
						if (busy < 50 || !wrap) {
							var s = args.join(", ");
							'($s) -> $r';
						} else {
							final s = args.join(',\n $indent');
							'($s)\n$indent-> $r';
						}
				}
		}
	}

	function printTypeRec<T>(t:JsonType<T>) {
		final old = indent;
		indent += "  ";
		final t = printType(t);
		indent = old;
		return t;
	}

	public function printFunctionArgument<T>(arg:JsonFunctionArgument) {
		final nullRemoval = arg.t.removeNulls();
		final concreteType = if (functionFormatting.explicitNull || !arg.opt) arg.t else nullRemoval.type;

		var argument = (if (arg.opt && arg.value == null) "?" else "") + arg.name;
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
		return if (functionFormatting.shouldPrintReturn(signature)) {
			":" + printTypeRec(signature.ret);
		} else {
			"";
		}
	}

	public function printEmptyFunctionDefinition<T>(name:String, signature:JsonFunctionSignature, ?params:JsonTypeParameters) {
		final printedParams = if (params == null) "" else printTypeParameters(params);
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
		final signature = concreteType.extractFunctionSignatureOrThrow();
		final returnKeyword = if (signature.ret.isVoid()) "" else "return ";
		final arguments = printCallArguments(signature, arg -> arg.name);
		final lineBreak = if (functionFormatting.placeOpenBraceOnNewLine) "\n" else " ";

		final definition = access + printEmptyFunctionDefinition(field.name, signature, field.params) + '$lineBreak{\n${indent}';
		final superCall = '${returnKeyword}super.${field.name}$arguments;';
		final end = '\n}';
		return if (snippets) {
			definition + '$${1:$superCall}$0$end';
		} else {
			definition + superCall + end;
		}
	}

	function printCommonFieldModifiers(buf:StringBuf, field:JsonClassField, moduleLevelField:Bool) {
		if (field.isPublic) {
			if (!moduleLevelField) {
				buf.add("public ");
			}
		} else if (functionFormatting.explicitPrivate) {
			buf.add("private ");
		}
		if (field.scope == Static && !moduleLevelField) {
			buf.add("static ");
		}
	}

	public function printMethodImplementation<T>(field:JsonClassField, concreteType:JsonType<T>, withOverride:Bool, moduleLevelField:Bool,
			expressions:Array<String>, tab:String = "\t") {
		var buf = new StringBuf();
		final signature = concreteType.extractFunctionSignatureOrThrow();
		final lineBreak = if (functionFormatting.placeOpenBraceOnNewLine) "\n" else " ";
		if (field.meta.hasMeta(Overload)) {
			buf.add("overload ");
		}
		if (withOverride) {
			buf.add("override ");
		}
		printCommonFieldModifiers(buf, field, moduleLevelField);

		buf.add(printEmptyFunctionDefinition(field.name, signature, field.params));
		buf.add(lineBreak);
		buf.add("{");
		if (expressions.length > 0) {
			for (expr in expressions) {
				buf.add("\n");
				buf.add(indent);
				buf.add(tab);
				buf.add(tab);
				buf.add(expr);
				buf.add(";");
			}
			buf.add("\n");
			buf.add(indent);
			buf.add(tab);
		}
		buf.add("}\n");
		return buf.toString();
	}

	public function printVarImplementation<T>(field:JsonClassField, args:{read:JsonVarAccess<Dynamic>, write:JsonVarAccess<Dynamic>},
			concreteType:JsonType<T>, moduleLevelField:Bool) {
		var buf = new StringBuf();
		printCommonFieldModifiers(buf, field, moduleLevelField);

		if (field.isFinalField()) {
			buf.add("final ");
			buf.add(field.name);
		} else {
			buf.add("var ");
			buf.add(field.name);
			buf.add(printAccessors(args));
		}
		buf.add(":");
		buf.add(printType(field.type));
		buf.add(";\n");
		return buf.toString();
	}

	public function printClassFieldImplementation<T>(field:JsonClassField, concreteType:JsonType<T>, withOverride:Bool, moduleLevelField:Bool,
			expressions:Array<String>, tab:String = "\t") {
		return switch (field.kind.kind) {
			case FMethod: printMethodImplementation(field, concreteType, withOverride, moduleLevelField, expressions, tab);
			case FVar: printVarImplementation(field, field.kind.args, concreteType, moduleLevelField);
		}
	}

	static final castRegex = ~/^(cast )+/;

	function printAccessors(args:{read:JsonVarAccess<Dynamic>, write:JsonVarAccess<Dynamic>}) {
		final read = printAccessor(args.read, true);
		final write = printAccessor(args.write, false);
		var accessors = if ((read != null && write != null) && (read != "default" || write != "default")) '($read, $write)' else "";
		return accessors;
	}

	public function printClassFieldDefinition<T0, T1, T2>(occurrence:ClassFieldOccurrence<T0>, concreteType:JsonType<T1>, isEnumAbstractField:Bool) {
		final field = occurrence.field;
		switch concreteType.kind {
			case TMono:
				concreteType = field.type;
			case _:
		}
		final type = printType(concreteType);
		var name = field.name;
		final kind:JsonFieldKind<T2> = field.kind;
		var access = if (field.isPublic) "public " else "private ";
		var staticKeyword = if (field.scope == Static && !occurrence.origin.isModuleLevel()) "static " else "";
		return switch kind.kind {
			case FVar:
				final inlineKeyword = if (kind.args.write.kind == AccInline) "inline " else "";
				final isFinal = kind.args.write.kind == AccCtor || field.isFinalField();
				final accessors = if (isFinal) "" else printAccessors(kind.args);
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
				final keyword = if (isFinal) "final" else "var";
				var definition = '$access$staticKeyword$keyword $inlineKeyword$name$accessors:$type';
				if (field.expr != null) {
					final expr = castRegex.replace(field.expr.string, "");
					definition += " = " + expr;
				}
				definition;
			case FMethod:
				final methodKind = switch kind.args {
					case MethNormal: "";
					case MethInline: "inline ";
					case MethDynamic: "dynamic ";
					case MethMacro: "macro ";
				}
				final finalKeyword = if (field.isFinalField()) "final " else "";
				final abstractKeyword = if (field.isAbstract) "abstract " else "";
				final methodSignature = concreteType.extractFunctionSignatureOrThrow();
				final definition = printEmptyFunctionDefinition(name, methodSignature, field.params);
				'$access$staticKeyword$finalKeyword$abstractKeyword$methodKind$definition';
		};
	}

	public function printAccessor<T>(access:JsonVarAccess<T>, isRead:Bool) {
		return switch access.kind {
			case AccNormal: "default";
			case AccNo: "null";
			case AccNever: "never";
			case AccResolve: null;
			#if (haxe_ver >= 5)
			case AccPrivateCall: "private " + if (isRead) "get" else "set";
			#end
			case AccCall: if (isRead) "get" else "set";
			case AccInline: null;
			case AccRequire: null;
			case AccCtor: null;
		}
	}

	public function printLocalDefinition<T1, T2>(local:DisplayLocal<T1>, concreteType:JsonType<T2>) {
		return switch local.origin {
			case LocalFunction:
				final inlineKeyword = if (local.isInline) "inline " else "";
				inlineKeyword + printEmptyFunctionDefinition(local.name, concreteType.extractFunctionSignatureOrThrow(),
					if (local.extra == null) null else local.extra.params);
			case other:
				var keyword = if (local.isFinal) "final " else "var ";
				var name = local.name;
				if (other == Argument) {
					keyword = "";
					if (concreteType.removeNulls().nullable) {
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
		final components = [];
		if (type.isPrivate)
			components.push("private");
		if (type.isFinalType())
			components.push("final");
		if (type.isExtern)
			components.push("extern");
		if (type.isAbstract)
			components.push("abstract");
		components.push(switch type.kind {
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

	public function printClassFieldOrigin<T>(origin:Null<ClassFieldOrigin<T>>, kind:DisplayItemKind<Dynamic>, quote:String = ""):Null<String> {
		if (origin == null) {
			return null;
		}
		if (kind == EnumAbstractField || origin.kind == cast Unknown) {
			return null;
		}
		if (origin.args == null && origin.kind != cast BuiltIn) {
			return null;
		}
		function printTypeKind(type:JsonModuleType<Dynamic>) {
			return switch type.kind {
				case Class: if (type.args.isInterface) "interface" else "class";
				case Enum: "enum";
				case Typedef: "typedef";
				case Abstract: if (type.meta.hasMeta(Enum)) "enum abstract" else "abstract";
			}
		}
		function printTypeInfo(type:JsonModuleType<Dynamic>) {
			final kind = if (origin.isModuleLevel()) "module" else printTypeKind(type);
			final name = quote + (if (origin.isModuleLevel()) type.moduleName else type.name) + quote;
			return kind + " " + name;
		}
		return "from " + @:nullSafety(Off) switch origin.kind {
			case Self:
				printTypeInfo(origin.args);
			case Parent:
				'parent ' + printTypeInfo(origin.args);
			case StaticExtension:
				printTypeInfo(origin.args) + ' (static extension method)';
			case StaticImport:
				printTypeInfo(origin.args) + ' (statically imported)';
			case AnonymousStructure:
				'anonymous structure';
			case BuiltIn:
				'compiler (built-in)';
			case Unknown:
				''; // already handled
		}
	}

	public function printEnumFieldOrigin<T>(origin:Null<EnumFieldOrigin<T>>, quote:String = ""):Null<String> {
		if (origin == null || origin.args == null) {
			return null;
		}
		return 'from enum ' + switch origin.kind {
			case Self:
				'$quote${origin.args.name}$quote';
			case StaticImport:
				'$quote${origin.args.name}$quote (statically imported)';
		}
	}

	public function printLocalOrigin(origin:LocalOrigin):String {
		return switch origin {
			case LocalVariable: "local variable";
			case Argument: "argument";
			case ForVariable: "for loop variable";
			case PatternVariable: "pattern variable";
			case CatchVariable: "catch variable";
			case LocalFunction: "local function";
		}
	}

	public inline function printEnumFieldDefinition<T>(field:JsonEnumField, concreteType:JsonType<T>) {
		return printEnumField(field, concreteType, false, true);
	}

	public function printEnumField<T>(field:JsonEnumField, concreteType:JsonType<T>, snippets:Bool, typeHints:Bool) {
		return switch concreteType.kind {
			case TEnum: field.name;
			case TFun:
				final signature:JsonFunctionSignature = concreteType.args;
				var text = '${field.name}(';
				for (i in 0...signature.args.length) {
					final arg = signature.args[i];
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
		final args = signature.args.map(arg -> {
			name: if (arg.name == "") null else arg.name,
			opt: arg.opt,
			type: new DisplayPrinter(PathPrinting.Never).printTypeRec(arg.t)
		});
		final names = IdentifierHelper.guessNames(args);
		var printedArgs = [];
		final singleArgument = args.length == 1;
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
		return if (functionFormatting.useArrowSyntax) {
			if (!singleArgument) {
				printedArguments = '($printedArguments)';
			}
			printedArguments + " -> ";
		} else {
			"function(" + printedArguments + ")" + printReturn(signature) + " ";
		}
	}

	public function printObjectLiteral(anon:JsonAnon, singleLine:Bool, onlyRequiredFields:Bool, snippets:Bool) {
		final printedFields = [];
		for (i in 0...anon.fields.length) {
			final field = anon.fields[i];
			final name = field.name;
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
		return if (printedFields.length == 0) {
			"{}";
		} else if (singleLine) {
			'{${printedFields.join(", ")}}';
		} else {
			'{\n${printedFields.join(",\n")}\n}';
		}
	}

	public function printSwitchSubject(subject:String, parentheses:Bool) {
		return "switch " + (if (parentheses) '($subject)' else subject);
	}

	public function printSwitchOnEnum(subject:String, e:JsonEnum, nullable:Bool, snippets:Bool, parentheses:Bool) {
		final fields = e.constructors.map(field -> printEnumField(field, field.type, false, false));
		return printSwitch(subject, fields, nullable, snippets, parentheses);
	}

	public function printSwitchOnEnumAbstract(subject:String, a:JsonAbstract, nullable:Bool, snippets:Bool, parentheses:Bool) {
		final fields = if (a.impl == null) [] else a.impl.statics.filter(f -> f.isEnumAbstractField()).map(field -> field.name);
		return printSwitch(subject, fields, nullable, snippets, parentheses);
	}

	public function printSwitch(subject:String, fields:Array<String>, nullable:Bool, snippets:Bool, parentheses:Bool) {
		if (nullable) {
			fields.unshift("null");
		}
		for (i in 0...fields.length) {
			var field = fields[i];
			field = '\tcase $field:';
			if (snippets) {
				field += "$" + (i + 1);
			}
			fields[i] = field;
		}
		return printSwitchSubject(subject, parentheses) + ' {\n${fields.join("\n")}\n}';
	}

	function printMetadataTarget(target:MetadataTarget):String {
		return switch target {
			case Class: "classes";
			case ClassField: "class fields";
			case Abstract: "abstracts";
			case AbstractField: "abstract fields";
			case Enum: "enums";
			case Typedef: "typedefs";
			case AnyField: "any field";
			case Expr: "expressions";
			case TypeParameter: "type parameters";
		}
	}

	function printPlatform(platform:Platform):String {
		return switch platform {
			case Cross: "cross";
			case Js: "JavaScript";
			case Lua: "Lua";
			case Neko: "Neko";
			case Flash: "Flash";
			case Php: "PHP";
			case Cpp: "C++";
			// case Cs: "C#";
			case cs if ('$cs' == "cs"): "C#";
			case Java: "Java";
			case Python: "Python";
			case Hl: "HashLink";
			case Eval: "Eval";
		}
	}

	public function printMetadataDetails(metadata:Metadata):String {
		var details = metadata.doc + "\n";
		inline function printList(name:String, list:Array<String>) {
			return if (list.length == 0) {
				"";
			} else {
				'- **$name:** ' + list.join(", ") + "\n";
			}
		}
		if (metadata.parameters != null) {
			details += printList("Parameters", metadata.parameters);
		}
		if (metadata.platforms != null) {
			details += printList("Targets", metadata.platforms.map(printPlatform));
		}
		if (metadata.targets != null) {
			details += printList("Can be used on", metadata.targets.map(printMetadataTarget));
		}
		if (metadata.links != null && metadata.links.length > 0) {
			details += metadata.links.map(link -> '- $link').join("\n");
		}
		if (metadata.internal) {
			details += "\n_compiler-internal_";
		}
		return details;
	}

	public function printArrayAccess(signature:JsonFunctionSignature) {
		final index = printFunctionArgument(signature.args[0]);
		return if (signature.args.length > 1) {
			// set
			var rhs = printFunctionArgument(signature.args[1]);
			'[$index] = $rhs';
		} else {
			// get
			var ret = printType(signature.ret);
			'[$index] -> $ret';
		}
	}
}

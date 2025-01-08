package haxeLanguageServer.features.haxe.codeAction.diagnostics;

import haxe.display.Diagnostic.MissingFieldCause;
import haxe.display.JsonModuleTypes;
import haxe.ds.Option;
import haxe.io.Path;
import haxeLanguageServer.features.haxe.DiagnosticsFeature;
import haxeLanguageServer.helper.ImportHelper;
import haxeLanguageServer.protocol.DisplayPrinter;
import sys.FileSystem;
import tokentree.TokenTree;

class MissingFieldsActions {
	public static function createMissingFieldsActions(context:Context, params:CodeActionParams, diagnostic:Diagnostic):Array<CodeAction> {
		if ((params.context.only != null) && (!params.context.only.contains(QuickFix))) {
			return [];
		}
		final args = context.diagnostics.getArguments(params.textDocument.uri, MissingFields, diagnostic.range);
		if (args == null) {
			return [];
		}
		final uri = new FsPath(args.moduleFile).toUri();
		var document = context.documents.getHaxe(uri);
		if (document == null) {
			// This is a bad pattern, but null-safety is trolling me hard with everything else...
			if (!FileSystem.exists(args.moduleFile)) {
				return [];
			}
			final content = sys.io.File.getContent(args.moduleFile);
			document = new HaxeDocument(uri, "haxe", 0, content);
		}
		var tokens = document.tokens ?? return [];
		var rangeClass:Null<Range> = null;
		var rangeFieldInsertion;
		var moduleLevelField = false;
		var className = args.moduleType.name;
		var classToken:Null<TokenTree> = null;
		switch (args.moduleType.kind) {
			case Class:
				classToken = getClassToken(tokens.tree, className);
				if (classToken == null) {
					moduleLevelField = true;
					final lastPos = document.content.length - 1;
					rangeFieldInsertion = document.rangeAt(lastPos, lastPos, Utf8);
				} else {
					final pos = tokens.getPos(classToken);
					rangeClass = document.rangeAt(pos.min, pos.min, Utf8);
					final pos = tokens.getTreePos(classToken);
					rangeFieldInsertion = document.rangeAt(pos.max - 1, pos.max - 1, Utf8);
				}
			case _:
				return [];
		}

		final actions:Array<CodeAction> = [];
		final importConfig = context.config.user.codeGeneration.imports;
		final fieldFormatting = context.config.user.codeGeneration.functions.field;
		final printer = new DisplayPrinter(false, if (importConfig.enableAutoImports) Shadowed else Qualified, fieldFormatting);
		final allEdits:Array<TextEdit> = [];
		final isSnippet = context.hasClientCommandSupport("haxe.codeAction.insertSnippet");
		var snippetEdit:Null<TextEdit> = null;
		var allDotPaths:Array<String> = [];
		// iterate all `MissingFields` diagnostic errors
		for (entry in args.entries) {
			// list of missing fields
			var fields = entry.fields.copy();
			function getTitle<T>(cause:MissingFieldCause<T>) {
				return switch (cause.kind) {
					case AbstractParent:
						// suggest `class` to `abstract class` action
						// or generate all missing fields for class that extends abstract class
						if (rangeClass != null) {
							final rangeClass:Range = rangeClass;
							actions.push({
								title: "Make abstract",
								kind: QuickFix,
								edit: WorkspaceEditHelper.create(document, [{range: rangeClass, newText: "abstract "}]),
								diagnostics: [diagnostic]
							});
						}
						Some('Implement methods for ${printer.printPathWithParams(cause.args.parent)}');
					case ImplementedInterface:
						Some('Implement fields for ${printer.printPathWithParams(cause.args.parent)}');
					case PropertyAccessor:
						Some('Implement ${cause.args.isGetter ? "getter" : "setter"} for ${cause.args.property.name}');
					case FieldAccess:
						// There's only one field in this case... I think
						final field = fields[0] ?? return None;
						final target = if (moduleLevelField) {
							Path.withoutDirectory(args.moduleFile).replace(".hx", "");
						} else {
							className;
						}
						Some('Add ${field.field.name} to $target');
					case FinalFields:
						// generate constructor for cases like:
						// class Foo {
						// 	final bar:Int;
						// }
						// with field args and `this.arg = arg` in body
						final funArgs:Array<JsonFunctionArgument> = [];
						final assignments:Array<String> = [];
						cause.args.fields.sort((cf1, cf2) -> cf1.pos.min - cf2.pos.min);
						for (field in cause.args.fields) {
							funArgs.push({
								name: field.name,
								opt: false,
								t: field.type
							});
							final name = field.name;
							assignments.push('this.$name = $name');
						}
						final ctorField = makeCtorJsonField(funArgs, assignments, args.moduleType.pos);
						fields.push({
							field: ctorField,
							type: ctorField.type,
							unique: false
						});
						Some('Add constructor to $className');
				}
			}
			final title = switch (getTitle(entry.cause)) {
				case Some(title): title;
				case None: return [];
			}
			final edits:Array<TextEdit> = [];
			// make only one edit in snippet mode, other as text
			var snippetEditId = -1;
			final getQualified = printer.collectQualifiedPaths();
			fields.sort((a, b) -> a.field.pos.min - b.field.pos.min);

			for (field in fields) {
				var buf = new StringBuf();
				buf.add(if (moduleLevelField) "\n\n" else "\n\t");
				final expressions:Array<String> = [];
				if (field.field.expr != null) {
					for (expr in field.field.expr.string.split("\n")) {
						expressions.push(expr);
					}
				} else {
					final signature = field.type.extractFunctionSignature();
					final args = signature?.args;
					if (args != null) {
						final isSnippetArgs = isSnippet && snippetEditId == -1;
						// hack to generate ${1:arg} snippet ranges for new function args
						renameGeneratedFunctionArgs(args, isSnippetArgs);
						if (isSnippetArgs) {
							snippetEditId = edits.length;
						}
					}
					if (signature.check(f -> !f.ret.isVoid())) {
						expressions.push("throw new haxe.exceptions.NotImplementedException()");
					}
				}
				buf.add(printer.printClassFieldImplementation(field.field, field.type, false, moduleLevelField, expressions));

				final isFunctionField = field.type.kind == TFun;
				if (classToken != null) {
					if (!isFunctionField) {
						final pos = getNewVariablePos(document, classToken, field.field.scope);
						if (pos != null)
							rangeFieldInsertion = pos.toRange();
					} else if (diagnostic.range != null) {
						final funToken = tokens?.getTokenAtOffset(document.offsetAt(diagnostic.range.start));
						if (funToken != null) {
							final pos = getNewClassFunctionPos(document, classToken, funToken);
							if (pos != null)
								rangeFieldInsertion = pos.toRange();
						}
					}
				}

				var bufStr = buf.toString();
				// keep additional newline only for added functions
				if (!isFunctionField && bufStr.endsWith("\n"))
					bufStr = bufStr.substr(0, bufStr.length - 1);
				final edit:TextEdit = {
					range: rangeFieldInsertion,
					newText: bufStr
				};
				edits.push(edit);
				if (field.unique) {
					allEdits.push(edit);
				}
			}

			var dotPaths = getQualified();
			dotPaths = dotPaths.filterDuplicates((a, b) -> a == b);
			allDotPaths = allDotPaths.concat(dotPaths);
			if (dotPaths.length > 0) {
				edits.push(createImportsEdit(document, determineImportPosition(document), dotPaths, importConfig.style));
			}
			final codeAction:CodeAction = {
				title: title,
				kind: QuickFix,
				diagnostics: [diagnostic]
			};
			snippetEdit = edits[snippetEditId];
			if (snippetEdit != null) {
				// wrap generated function body to `{0:...}` snippet range
				var text = snippetEdit.newText;
				final matchBodyExpr = ~/({\n[\t ]+)(.+)\n/;
				if (matchBodyExpr.match(text)) {
					text = matchBodyExpr.replace(text, '$1$${0:$2}\n');
				}
				codeAction.command = {
					title: "Insert Snippet",
					command: "haxe.codeAction.insertSnippet",
					arguments: [document.uri.toString(), rangeFieldInsertion, text]
				}
			} else {
				codeAction.edit = WorkspaceEditHelper.create(document, edits);
				if (entry.cause.kind == FieldAccess) {
					codeAction.command = {
						title: "Highlight Insertion",
						command: "haxe.codeAction.highlightInsertion",
						arguments: [document.uri.toString(), rangeFieldInsertion]
					}
				}
			}
			actions.unshift(codeAction);
		}

		// generate all missing fields action only if there is more than one diagnostic error
		if (args.entries.length > 1) {
			allDotPaths = allDotPaths.filterDuplicates((a, b) -> a == b);
			if (allDotPaths.length > 0) {
				allEdits.push(createImportsEdit(document, determineImportPosition(document), allDotPaths, importConfig.style));
			}
			final action:CodeAction = {
				title: "Implement all missing fields",
				kind: QuickFix,
				diagnostics: [diagnostic]
			};
			if (snippetEdit != null) {
				final item = allEdits.find(item -> item.newText == snippetEdit.newText);
				if (item != null)
					allEdits.remove(item);
				action.command = {
					title: "Insert Snippet",
					command: "haxe.codeAction.insertSnippet",
					arguments: [document.uri.toString(), snippetEdit.range, snippetEdit.newText]
				}
			}
			action.edit = WorkspaceEditHelper.create(document, allEdits);
			actions.unshift(action);
		}
		if (actions.length > 0) {
			actions[0].isPreferred = true;
		}
		return actions;
	}

	static function getClassToken(tree:TokenTree, className:String):Null<TokenTree> {
		final classTokens = tree.filterCallback((token, _) -> {
			return switch (token.tok) {
				case Kwd(KwdClass):
					FoundSkipSubtree;
				case Sharp(_):
					GoDeeper;
				case _:
					SkipSubtree;
			}
		});
		for (token in classTokens) {
			final nameToken = token.getNameToken() ?? continue;
			if (nameToken.getName() == className) {
				return token;
			}
		}
		return null;
	}

	static function makeCtorJsonField(funArgs:Array<JsonFunctionArgument>, assignments:Array<String>, pos:JsonPos):JsonClassField {
		final ctorField:JsonClassField = {
			name: "new",
			type: {
				kind: TFun,
				args: {
					args: funArgs,
					ret: {
						kind: TMono,
						args: null
					}
				}
			},
			isPublic: true,
			isFinal: false,
			isAbstract: false,
			params: [],
			meta: [],
			kind: {
				kind: FMethod,
				args: MethNormal
			},
			pos: pos,
			doc: null,
			overloads: [],
			scope: Constructor,
			expr: {
				string: assignments.join("\n")
			}
		}
		return ctorField;
	}

	static function renameGeneratedFunctionArgs(args:Array<JsonFunctionArgument>, isSnippetArgs:Bool) {
		final argNames = [];
		var id = 0;
		for (arg in args) {
			var argName = arg.name;
			if (argName.startsWith("arg") && argName.length == 4) {
				argName = MissingArgumentsAction.genArgNameFromJsonType(arg.t);
			}
			for (i in 1...10) {
				final name = argName + (i == 1 ? "" : '$i');
				if (!argNames.contains(name)) {
					argNames.push(name);
					argName = name;
					break;
				}
			}
			id++;
			if (arg.name.startsWith("${"))
				continue;
			arg.name = isSnippetArgs ? '$${$id:$argName}' : argName;
		}
	}

	static function getNewVariablePos(document:HaxeDocument, classToken:TokenTree, fieldScope:JsonClassFieldScope):Null<Position> {
		final brOpen = classToken.access().firstChild().firstOf(BrOpen)?.token;
		if (brOpen == null) {
			return null;
		}
		// add statics to the top
		if (fieldScope == Static) {
			return document.positionAt(brOpen.pos.max, Utf8);
		}
		// find place for field before first function in class
		final firstFun = brOpen.access().firstOf(Kwd(KwdFunction));
		var prev = firstFun?.token?.previousSibling;
		while (prev != null && prev.isComment()) {
			prev = prev.previousSibling;
		}
		// if function is first add var at the top
		if (prev == null) {
			return document.positionAt(brOpen.pos.max, Utf8);
		}
		final pos = prev.getPos();
		return document.positionAt(pos.max, Utf8);
	}

	static function getNewClassFunctionPos(document:HaxeDocument, classToken:TokenTree, callToken:TokenTree):Null<Position> {
		final brOpen = classToken.access().firstChild().firstOf(BrOpen)?.token;
		if (brOpen == null) {
			return null;
		}
		if (brOpen.filter([callToken.tok], First).length == 0)
			return null;

		// find place for function after current function in class
		final callPos = callToken.getPos();
		for (i => token in brOpen.children) {
			final tokenPos = token.getPos();
			if (callPos.min < tokenPos.min || callPos.min > tokenPos.max)
				continue;
			if (token.tok.match(Kwd(KwdFunction))) {
				return document.positionAt(tokenPos.max + 1, Utf8);
			}
		}
		return null;
	}
}

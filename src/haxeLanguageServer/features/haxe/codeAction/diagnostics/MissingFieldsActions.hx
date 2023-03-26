package haxeLanguageServer.features.haxe.codeAction.diagnostics;

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
		var tokens = document.tokens;
		if (tokens == null) {
			return [];
		}
		var rangeClass:Null<Range> = null;
		var rangeFieldInsertion;
		var moduleLevelField = false;
		var className = args.moduleType.name;
		var classToken:Null<TokenTree> = null;
		switch (args.moduleType.kind) {
			case Class:
				var classTokens = tokens.tree.filterCallback((token, _) -> {
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
					var nameToken = token.getNameToken();
					if (nameToken == null) {
						continue;
					}
					var name = nameToken.getName();
					if (name == className) {
						classToken = token;
					}
				}
				if (classToken == null) {
					moduleLevelField = true;
					final lastPos = document.content.length - 1;
					rangeFieldInsertion = document.rangeAt(lastPos, lastPos);
				} else {
					var pos = tokens.getPos(classToken);
					rangeClass = document.rangeAt(pos.min, pos.min);
					var pos = tokens.getTreePos(classToken);
					rangeFieldInsertion = document.rangeAt(pos.max - 1, pos.max - 1);
				}
			case _:
				return [];
		}

		var actions:Array<CodeAction> = [];
		final importConfig = context.config.user.codeGeneration.imports;
		final fieldFormatting = context.config.user.codeGeneration.functions.field;
		final printer = new DisplayPrinter(false, if (importConfig.enableAutoImports) Shadowed else Qualified, fieldFormatting);
		var allEdits = [];
		var allDotPaths = [];
		for (entry in args.entries) {
			var fields = entry.fields.copy();
			function getTitle<T>(cause:MissingFieldCause<T>) {
				return switch (cause.kind) {
					case AbstractParent:
						if (rangeClass != null) {
							@:nullSafety(Off)
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
						var field = fields[0];
						if (field == null) {
							return None;
						}
						final target = if (moduleLevelField) {
							Path.withoutDirectory(args.moduleFile).replace(".hx", "");
						} else {
							className;
						}
						Some('Add ${field.field.name} to $target');
					case FinalFields:
						final funArgs = [];
						final assignments = [];
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
							pos: args.moduleType.pos,
							doc: null,
							overloads: [],
							scope: Constructor,
							expr: {
								string: assignments.join("\n")
							}
						}
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
			var edits = [];
			final getQualified = printer.collectQualifiedPaths();
			fields.sort((a, b) -> a.field.pos.min - b.field.pos.min);
			for (field in fields) {
				var buf = new StringBuf();
				buf.add(if (moduleLevelField) "\n\n" else "\n\t");
				final expressions = [];
				if (field.field.expr != null) {
					for (expr in field.field.expr.string.split("\n")) {
						expressions.push(expr);
					}
				} else if (field.type.extractFunctionSignature().check(f -> !f.ret.isVoid())) {
					expressions.push("throw new haxe.exceptions.NotImplementedException()");
				}
				buf.add(printer.printClassFieldImplementation(field.field, field.type, false, moduleLevelField, expressions));

				if (classToken != null) {
					if (field.type.kind != TFun) {
						final range = getNewVariablePos(document, classToken, field.field.scope);
						if (range != null)
							rangeFieldInsertion = range;
					} else {
						final funToken = tokens!.getTokenAtOffset(document.offsetAt(diagnostic.range.start));
						if (funToken != null) {
							final range = getNewClassFunctionPos(document, classToken, funToken);
							if (range != null)
								rangeFieldInsertion = range;
						}
					}
				}

				var edit = {
					range: rangeFieldInsertion,
					newText: buf.toString()
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
				edit: WorkspaceEditHelper.create(document, edits),
				diagnostics: [diagnostic]
			};
			if (entry.cause.kind == FieldAccess) {
				codeAction.command = {
					title: "Highlight Insertion",
					command: "haxe.codeAction.highlightInsertion",
					arguments: [document.uri.toString(), rangeFieldInsertion]
				}
			}
			actions.unshift(codeAction);
		}
		if (args.entries.length > 1) {
			allDotPaths = allDotPaths.filterDuplicates((a, b) -> a == b);
			if (allDotPaths.length > 0) {
				allEdits.push(createImportsEdit(document, determineImportPosition(document), allDotPaths, importConfig.style));
			}
			actions.unshift({
				title: "Implement all missing fields",
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(document, allEdits),
				diagnostics: [diagnostic]
			});
		}
		if (actions.length > 0) {
			actions[0].isPreferred = true;
		}
		return actions;
	}

	static function getNewVariablePos(document:HaxeDocument, classToken:TokenTree, fieldScope:JsonClassFieldScope):Null<Range> {
		final brOpen = classToken.access().firstChild().firstOf(BrOpen)!.token;
		if (brOpen == null) {
			return null;
		}
		// add statics to the top
		if (fieldScope == Static) {
			return document.rangeAt(brOpen.pos.max, brOpen.pos.max);
		}
		// find place for field before first function in class
		final firstFun = brOpen.access().firstOf(Kwd(KwdFunction));
		final prev = firstFun!.token!.previousSibling;
		// if function is first add var at the top
		if (prev == null) {
			return document.rangeAt(brOpen.pos.max, brOpen.pos.max);
		}
		final pos = prev.getPos();
		return document.rangeAt(pos.max, pos.max);
	}

	static function getNewClassFunctionPos(document:HaxeDocument, classToken:TokenTree, callToken:TokenTree):Null<Range> {
		final brOpen = classToken.access().firstChild().firstOf(BrOpen)!.token;
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
				return document.rangeAt(tokenPos.max + 1, tokenPos.max + 1);
			}
		}
		return null;
	}
}

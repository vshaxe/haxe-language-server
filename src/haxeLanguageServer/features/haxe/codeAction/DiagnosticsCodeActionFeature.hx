package haxeLanguageServer.features.haxe.codeAction;

import haxe.display.Display.DisplayItem;
import haxe.display.Display.DisplayMethods;
import haxe.display.Display.HoverDisplayItemOccurence;
import haxe.display.JsonModuleTypes;
import haxe.ds.Option;
import haxe.io.Path;
import haxeLanguageServer.Configuration;
import haxeLanguageServer.features.haxe.DiagnosticsFeature.*;
import haxeLanguageServer.features.haxe.DiagnosticsFeature;
import haxeLanguageServer.features.haxe.InlayHintFeature.HoverRequestContext;
import haxeLanguageServer.features.haxe.codeAction.CodeActionFeature;
import haxeLanguageServer.features.haxe.codeAction.OrganizeImportsFeature;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.helper.ImportHelper;
import haxeLanguageServer.helper.TypeHelper;
import haxeLanguageServer.helper.WorkspaceEditHelper;
import haxeLanguageServer.protocol.DisplayPrinter;
import js.lib.Promise;
import jsonrpc.CancellationToken;
import languageServerProtocol.Types.CodeAction;
import languageServerProtocol.Types.DefinitionLink;
import languageServerProtocol.Types.Diagnostic;
import sys.FileSystem;
import tokentree.TokenTree;

using Lambda;
using tokentree.TokenTreeAccessHelper;
using tokentree.utils.TokenTreeCheckUtils;

private enum FieldInsertionMode {
	IntoClass(rangeClass:Range, rangeEnd:Range);
}

class DiagnosticsCodeActionFeature implements CodeActionContributor {
	final context:Context;
	final diagnostics:DiagnosticsFeature;

	public function new(context, diagnostics) {
		this.context = context;
		this.diagnostics = diagnostics;
	}

	public function createCodeActions<T>(params:CodeActionParams) {
		if (!params.textDocument.uri.isFile()) {
			return [];
		}
		var actions:Array<CodeAction> = [];
		for (diagnostic in params.context.diagnostics) {
			if (diagnostic.code == null || !(diagnostic.code is Int)) { // our codes are int, so we don't handle other stuff
				continue;
			}
			final code = new DiagnosticKind<T>(diagnostic.code);
			actions = actions.concat(switch code {
				case UnusedImport: createUnusedImportActions(params, diagnostic);
				case UnresolvedIdentifier: createUnresolvedIdentifierActions(params, diagnostic);
				case CompilerError: createCompilerErrorActions(params, diagnostic);
				case RemovableCode: createRemovableCodeActions(params, diagnostic);
				case MissingFields: createMissingFieldsActions(params, diagnostic);
				case _: [];
			});
		}
		actions = createOrganizeImportActions(params, actions).concat(actions);
		actions = actions.filterDuplicates((a, b) -> a.title == b.title);
		return actions;
	}

	function createUnusedImportActions(params:CodeActionParams, diagnostic:Diagnostic):Array<CodeAction> {
		final doc = context.documents.getHaxe(params.textDocument.uri);
		if (doc == null) {
			return [];
		}
		return [
			{
				title: RemoveUnusedImportUsingTitle,
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, [
					{
						range: DocHelper.untrimRange(doc, diagnostic.range),
						newText: ""
					}
				]),
				diagnostics: [diagnostic],
				isPreferred: true
			}
		];
	}

	function createUnresolvedIdentifierActions(params:CodeActionParams, diagnostic:Diagnostic):Array<CodeAction> {
		final args = diagnostics.getArguments(params.textDocument.uri, UnresolvedIdentifier, diagnostic.range);
		if (args == null) {
			return [];
		}
		var actions:Array<CodeAction> = [];
		final importCount = args.count(a -> a.kind == Import);
		for (arg in args) {
			actions = actions.concat(switch arg.kind {
				case Import: createUnresolvedImportActions(params, diagnostic, arg, importCount);
				case Typo: createTypoActions(params, diagnostic, arg);
			});
		}
		return actions;
	}

	function createUnresolvedImportActions(params:CodeActionParams, diagnostic:Diagnostic, arg, importCount:Int):Array<CodeAction> {
		final doc = context.documents.getHaxe(params.textDocument.uri);
		if (doc == null) {
			return [];
		}
		final preferredStyle = context.config.user.codeGeneration.imports.style;
		final secondaryStyle:ImportStyle = if (preferredStyle == Type) Module else Type;

		final importPosition = determineImportPosition(doc);
		function makeImportAction(style:ImportStyle):CodeAction {
			final path = if (style == Module) TypeHelper.getModule(arg.name) else arg.name;
			return {
				title: "Import " + path,
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, [createImportsEdit(doc, importPosition, [arg.name], style)]),
				diagnostics: [diagnostic]
			};
		}

		final preferred = makeImportAction(preferredStyle);
		final secondary = makeImportAction(secondaryStyle);
		if (importCount == 1) {
			preferred.isPreferred = true;
		}
		final actions = [preferred, secondary];

		actions.push({
			title: "Change to " + arg.name,
			kind: QuickFix,
			edit: WorkspaceEditHelper.create(context, params, [
				{
					range: diagnostic.range,
					newText: arg.name
				}
			]),
			diagnostics: [diagnostic]
		});

		return actions;
	}

	function createTypoActions(params:CodeActionParams, diagnostic:Diagnostic, arg):Array<CodeAction> {
		return [
			{
				title: "Change to " + arg.name,
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, [{range: diagnostic.range, newText: arg.name}]),
				diagnostics: [diagnostic]
			}
		];
	}

	function createCompilerErrorActions(params:CodeActionParams, diagnostic:Diagnostic):Array<CodeAction> {
		final actions:Array<CodeAction> = [];
		final arg = diagnostics.getArguments(params.textDocument.uri, CompilerError, diagnostic.range);
		if (arg == null) {
			return actions;
		}
		final suggestionsRe = ~/\(Suggestions?: (.*)\)/;
		if (suggestionsRe.match(arg)) {
			final suggestions = suggestionsRe.matched(1).split(",");
			// Haxe reports the entire expression, not just the field position, so we have to be a bit creative here.
			final range = diagnostic.range;
			final fieldRe = ~/has no field ([^ ]+) /;
			if (fieldRe.match(arg)) {
				range.start.character = range.end.character - fieldRe.matched(1).length;
			}
			for (suggestion in suggestions) {
				suggestion = suggestion.trim();
				actions.push({
					title: "Change to " + suggestion,
					kind: QuickFix,
					edit: WorkspaceEditHelper.create(context, params, [{range: range, newText: suggestion}]),
					diagnostics: [diagnostic]
				});
			}
			return actions;
		}

		final invalidPackageRe = ~/Invalid package : ([\w.]*) should be ([\w.]*)/;
		if (invalidPackageRe.match(arg)) {
			final is = invalidPackageRe.matched(1);
			final shouldBe = invalidPackageRe.matched(2);
			final document = context.documents.getHaxe(params.textDocument.uri);
			if (document != null) {
				final replacement = document.getText(diagnostic.range).replace(is, shouldBe);
				actions.push({
					title: "Change to " + replacement,
					kind: QuickFix,
					edit: WorkspaceEditHelper.create(context, params, [{range: diagnostic.range, newText: replacement}]),
					diagnostics: [diagnostic],
					isPreferred: true
				});
			}
		}

		if (context.haxeServer.haxeVersion.major >= 4 // unsuitable error range before Haxe 4
			&& arg.contains("should be declared with 'override' since it is inherited from superclass")) {
			var pos = diagnostic.range.start;
			final document = context.documents.getHaxe(params.textDocument.uri);
			if (document.tokens != null) {
				// Resolve parent token to add "override" before "fnunction" instead of function name
				final funPos = document.tokens!.getTokenAtOffset(document.offsetAt(diagnostic.range.start))!.parent!.pos!.min;
				if (funPos != null) {
					pos = document.positionAt(funPos);
				}
			}
			actions.push({
				title: "Add override keyword",
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, [{range: pos.toRange(), newText: "override "}]),
				diagnostics: [diagnostic],
				isPreferred: true
			});
		}

		final tooManyArgsRe = ~/Too many arguments([\w.]*)/;
		if (tooManyArgsRe.match(arg)) {
			final document = context.documents.getHaxe(params.textDocument.uri);
			final replacement = document.getText(diagnostic.range);
			actions.push({
				title: "Add argument",
				data: CodeActionFeature.addResolveData(MissingArg(action -> createMissingArgumentsAction(action, params, diagnostic))),
				kind: QuickFix,
				diagnostics: [diagnostic],
				isPreferred: true,
			});
		}
		return actions;
	}

	function createMissingArgumentsAction(action:CodeAction, params:CodeActionParams, diagnostic:Diagnostic):Null<Promise<CodeAction>> {
		final document = context.documents.getHaxe(params.textDocument.uri);
		if (document == null)
			return null;
		var fileName:String = document.uri.toFsPath().toString();
		final pos = document.offsetAt(diagnostic.range.start);
		var tokenSource = new CancellationTokenSource();
		final gotoDefinition = new GotoDefinitionFeature(context, false);

		final argToken = document.tokens!.getTokenAtOffset(document.offsetAt(diagnostic.range.start));
		if (argToken == null)
			return null;
		final funPos = getCallNamePos(document, argToken);
		if (funPos == null)
			return null;
		final gotoPromise = new Promise(function(resolve:(hover:Array<DefinitionLink>) -> Void, reject) {
			gotoDefinition.onGotoDefinition({
				textDocument: params.textDocument,
				position: funPos.start
			}, tokenSource.token, array -> {
				resolve(array);
			}, error -> reject(error));
		});
		final hoverPromise = makeHoverRequest(fileName, pos, tokenSource.token);

		final actionPromise = Promise.all([gotoPromise, hoverPromise]).then(results -> {
			final definitions:Array<DefinitionLink> = results[0];
			// TODO investigate multiple definitions case
			final definition = definitions[0] ?? return action;
			final hover:HoverDisplayItemOccurence<Dynamic> = results[1];
			final printer = new DisplayPrinter(true, Qualified, {
				argumentTypeHints: true,
				returnTypeHint: Always,
				useArrowSyntax: true,
				placeOpenBraceOnNewLine: false,
				explicitPublic: true,
				explicitPrivate: true,
				explicitNull: true
			});
			final item = hover.item;
			final itemType = item.type;
			if (itemType == null)
				return action;
			final type = itemType.removeNulls().type;
			final typeHint = printer.printType(type);
			final definitionDoc = context.documents.getHaxe(definition.targetUri);
			if (definitionDoc == null)
				return action;
			final definitonFunToken = definitionDoc.tokens!.getTokenAtOffset(definitionDoc.offsetAt(definition.targetSelectionRange.start));
			final argRange = functionNewArgPos(definitionDoc, definitonFunToken) ?? return action;
			final hadCommaAtEnd = functionArgsEndsWithComma(definitionDoc, definitonFunToken);
			var argName = generateArgName(item);
			final argNames = getArgsNames(definitionDoc, definitonFunToken);
			for (i in 1...10) {
				final name = argName + (i == 1 ? "" : '$i');
				if (!argNames.contains(name)) {
					argName = name;
					break;
				}
			}
			var arg = '$argName';
			if (typeHint != "?")
				arg += ':$typeHint';
			if (functionArgsCount(definitionDoc, definitonFunToken) > 0) {
				arg = hadCommaAtEnd ? ' $arg' : ', $arg';
			}
			action.edit = WorkspaceEditHelper.create(definitionDoc, [{range: argRange, newText: arg}]);
			action.command = {
				title: "Highlight Insertion",
				command: "haxe.codeAction.highlightInsertion",
				arguments: [definitionDoc.uri.toString(), argRange]
			}
			return action;
		});
		return actionPromise;
	}

	function generateArgName(item:DisplayItem<Dynamic>):String {
		switch item.kind {
			case Literal:
			case AnonymousStructure:
				return "obj";
			case Expression:
				if (item.type!.kind == TFun)
					return "callback";
			case _:
				return item.args!.name ?? "arg";
		}
		final dotPath = item.type!.getDotPath() ?? return "arg";
		return switch dotPath {
			case Std_Bool: "bool";
			case Std_Int, Std_UInt: "i";
			case Std_Float: "f";
			case Std_String: "s";
			case Std_Array, Haxe_Ds_ReadOnlyArray: "arr";
			case Std_EReg: "regExp";
			case Std_Dynamic: "value";
			case Haxe_Ds_Map: "map";
			case _: "arg";
		}
	}

	function getArgsNames(document:HaxeDocument, funIdent:Null<TokenTree>):Array<String> {
		final pOpen = getFunctionPOpen(funIdent) ?? return [];
		final args = pOpen.filterCallback((tree, depth) -> {
			if (depth == 0)
				GoDeeper;
			else
				tree.isCIdent() ? FoundSkipSubtree : SkipSubtree;
		});
		return args.map(tree -> tree.toString());
	}

	function makeHoverRequest<T>(fileName:String, pos:Int, token:CancellationToken):Promise<Null<HoverDisplayItemOccurence<T>>> {
		var request:HoverRequestContext<T> = {
			params: cast {
				file: cast fileName,
				offset: pos
			},
			token: token,
			resolve: null
		}
		var promise = new Promise(function(resolve:(hover:Null<HoverDisplayItemOccurence<T>>) -> Void, reject) {
			request.resolve = resolve;
		});
		context.callHaxeMethod(DisplayMethods.Hover, request.params, request.token, function(hover) {
			if (request.resolve != null) {
				if (hover == null) {
					request.resolve(null);
				} else {
					request.resolve(hover);
				}
			}
			return null;
		}, function(msg) {
			if (request.resolve != null) {
				request.resolve(null);
			}
			return;
		});
		return promise;
	}

	function createRemovableCodeActions(params:CodeActionParams, diagnostic:Diagnostic):Array<CodeAction> {
		final range = diagnostics.getArguments(params.textDocument.uri, RemovableCode, diagnostic.range)!.range;
		if (range == null) {
			return [];
		}
		return [
			{
				title: "Remove",
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, @:nullSafety(Off) [{range: range, newText: ""}]),
				diagnostics: [diagnostic],
				isPreferred: true
			}
		];
	}

	function createOrganizeImportActions(params:CodeActionParams, existingActions:Array<CodeAction>):Array<CodeAction> {
		final uri = params.textDocument.uri;
		final doc = context.documents.getHaxe(uri);
		if (doc == null) {
			return [];
		}
		final map = diagnostics.getArgumentsMap(uri);
		final removeUnusedFixes = if (map == null) [] else [
			for (key in map.keys()) {
				if (key.code == UnusedImport) {
					WorkspaceEditHelper.removeText(DocHelper.untrimRange(doc, key.range));
				}
			}
		];

		final sortFixes = OrganizeImportsFeature.organizeImports(doc, context, []);

		final unusedRanges:Array<Range> = removeUnusedFixes.map(edit -> edit.range);
		final organizeFixes = removeUnusedFixes.concat(OrganizeImportsFeature.organizeImports(doc, context, unusedRanges));

		@:nullSafety(Off) // ?
		final diagnostics = existingActions.filter(action -> action.title == RemoveUnusedImportUsingTitle)
			.map(action -> action.diagnostics)
			.flatten()
			.array();
		final actions:Array<CodeAction> = [
			{
				title: SortImportsUsingsTitle,
				kind: CodeActionFeature.SourceSortImports,
				edit: WorkspaceEditHelper.create(context, params, sortFixes)
			},
			{
				title: OrganizeImportsUsingsTitle,
				kind: SourceOrganizeImports,
				edit: WorkspaceEditHelper.create(context, params, organizeFixes),
				diagnostics: diagnostics
			}
		];

		if (diagnostics.length > 0 && removeUnusedFixes.length > 1) {
			actions.push({
				title: RemoveAllUnusedImportsUsingsTitle,
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, removeUnusedFixes),
				diagnostics: diagnostics
			});
		}

		return actions;
	}

	function createMissingFieldsActions(params:CodeActionParams, diagnostic:Diagnostic):Array<CodeAction> {
		final args = diagnostics.getArguments(params.textDocument.uri, MissingFields, diagnostic.range);
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

	function getNewVariablePos(document:HaxeDocument, classToken:TokenTree, fieldScope:JsonClassFieldScope):Null<Range> {
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

	function getNewClassFunctionPos(document:HaxeDocument, classToken:TokenTree, callToken:TokenTree):Null<Range> {
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

	function getCallNamePos(document:HaxeDocument, argToken:TokenTree):Null<Range> {
		final parent = argToken.access().findParent(helper -> {
			return switch (helper!.token!.tok) {
				case Const(CIdent(_)): true;
				case _: false;
			}
		});
		if (parent == null) {
			return null;
		}
		final tokenPos = parent.token.pos;
		return document.rangeAt(tokenPos.min, tokenPos.max);
	}

	function getFunctionPOpen(funIdent:Null<TokenTree>):Null<TokenTree> {
		if (funIdent == null)
			return null;
		// Check for: var foo:()->Void = ...
		final isFunction = switch (funIdent!.parent!.tok) {
			case Kwd(KwdFunction): true;
			case _: false;
		}
		if (!isFunction) {
			funIdent = funIdent.getFirstChild() ?? return null;
		}
		final pOpen = funIdent.access().firstOf(POpen)!.token;
		return pOpen;
	}

	function functionNewArgPos(document:HaxeDocument, funIdent:Null<TokenTree>):Null<Range> {
		final pOpen = getFunctionPOpen(funIdent);
		if (pOpen == null) {
			return null;
		}
		final pClose = pOpen.access().firstOf(PClose)!.token;
		if (pClose == null) {
			return null;
		}
		return document.rangeAt(pClose.pos.min, pClose.pos.min);
	}

	function functionArgsCount(document:HaxeDocument, funIdent:Null<TokenTree>):Int {
		final pOpen = getFunctionPOpen(funIdent) ?? return 0;
		final args = pOpen.filterCallback((tree, depth) -> {
			if (depth == 0)
				GoDeeper;
			else
				tree.isCIdent() ? FoundSkipSubtree : SkipSubtree;
		});
		return args.length;
	}

	function functionArgsEndsWithComma(document:HaxeDocument, funIdent:Null<TokenTree>):Bool {
		final pOpen = getFunctionPOpen(funIdent) ?? return false;
		final maybeComma = pOpen.getLastChild()!.getLastChild();
		if (maybeComma == null) {
			return false;
		}
		return maybeComma.matches(Comma);
	}
}

package haxeLanguageServer.features.hxml;

import haxe.io.Path;
import haxeLanguageServer.features.hxml.HxmlContextAnalyzer;
import haxeLanguageServer.features.hxml.data.Defines;
import haxeLanguageServer.features.hxml.data.Flags;
import haxeLanguageServer.features.hxml.data.Shared;
import haxeLanguageServer.helper.TextEditCompletionItem;
import haxeLanguageServer.helper.VscodeCommands;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import sys.FileSystem;

using Lambda;

class CompletionFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
	}

	public function onCompletion(params:CompletionParams, token:CancellationToken, resolve:CompletionList->Void, reject:ResponseError<NoData>->Void) {
		final uri = params.textDocument.uri;
		final doc = context.documents.getHxml(uri);
		if (doc == null) {
			return reject.noFittingDocument(uri);
		}
		final pos = params.position;
		final line = doc.lineAt(pos.line);
		final textBefore = line.substr(0, pos.character);
		final textAfter = line.substr(pos.character);
		final hxmlContext = analyzeHxmlContext(textBefore, pos);

		function resolveItems(items) {
			resolve({
				isIncomplete: false,
				items: items
			});
		}
		final range = hxmlContext.range;
		switch hxmlContext.element {
			case Flag(_):
				resolveItems(createFlagCompletion(range, textAfter));
			case EnumValue(_, values):
				resolveItems(createEnumValueCompletion(range, values));
			case Define():
				resolveItems(createDefineCompletion(range));
			case File(path):
				resolveItems(createFilePathCompletion(range, path, true));
			case Directory(path):
				resolveItems(createFilePathCompletion(range, path, false));
			case LibraryName(_):
				createLibraryNameCompletion(range, resolve, reject);
			case DefineValue(_) | Unknown:
				[];
		}
	}

	function createFlagCompletion(range:Range, textAfter:String):Array<CompletionItem> {
		final items = [];
		function addFlag(flag:Flag, name:String) {
			final item:TextEditCompletionItem = {
				label: name,
				textEdit: {
					range: range,
					newText: name
				},
				filterText: name,
				kind: Function,
				documentation: {
					kind: MarkDown,
					value: flag.description
				},
				insertTextFormat: Snippet
			}
			final arg = flag.argument;
			if (arg != null) {
				item.label += " " + arg.name;
				if (textAfter.charAt(0) != " ") {
					item.textEdit.newText += " ";
				}
				if (arg.insertion != null) {
					var insertion = arg.insertion;
					if (!insertion.contains("$")) {
						insertion = '$${1:$insertion}';
					}
					item.textEdit.newText += insertion;
				}
				if (arg.kind != null) {
					item.command = TriggerSuggest;
				}
			}
			items.push(item);
		}
		for (flag in HxmlFlags.flatten()) {
			addFlag(flag, flag.name);
			if (flag.shortName != null) {
				addFlag(flag, flag.shortName);
			}
		}
		return items;
	}

	function createEnumValueCompletion(range, values:EnumValues):Array<CompletionItem> {
		final items:Array<CompletionItem> = [
			for (value in values)
				{
					label: value.name,
					kind: EnumMember,
					textEdit: {
						range: range,
						newText: value.name
					},
					documentation: value.description
				}
		];
		items[0].preselect = true;
		return items;
	}

	function createDefineCompletion(range:Range):Array<CompletionItem> {
		final haxeVersion = context.haxeServer.haxeVersion;
		return getDefines(false).map(define -> {
			final name = define.getRealName();
			final item:CompletionItem = {
				label: name,
				kind: Constant,
				textEdit: {
					range: range,
					newText: name
				},
				documentation: {
					kind: MarkDown,
					value: define.printDetails(haxeVersion)
				}
			}
			if (define.hasParams()) {
				item.insertText = item.label + "=";
				item.command = TriggerSuggest;
			}
			if (!define.isAvailable(haxeVersion)) {
				item.tags = [Deprecated];
			}
			return item;
		});
	}

	final IgnoredFiles:ReadOnlyArray<String> = ["haxe_libraries", "node_modules", "dump"];

	function createFilePathCompletion(range:Range, path:Null<String>, includeFiles:Bool):Array<CompletionItem> {
		if (path == null) {
			path = "";
		}
		function isValidDirectory(path) {
			return FileSystem.exists(path) && FileSystem.isDirectory(path);
		}
		var directory = if ((path.endsWith("/") || path.endsWith("\\")) && isValidDirectory(path)) path else Path.directory(path);
		if (directory.trim() == "") {
			directory = ".";
		}
		if (!isValidDirectory(directory)) {
			return [];
		}
		final items = new Array<CompletionItem>();
		for (file in FileSystem.readDirectory(directory)) {
			if (file.startsWith(".") || file.startsWith("$") || IgnoredFiles.contains(file)) {
				continue;
			}
			final fullPath = Path.join([directory, file]);
			final isDirectory = FileSystem.isDirectory(fullPath);
			if (!includeFiles && !isDirectory) {
				continue;
			}
			final item:CompletionItem = {
				label: file,
				kind: if (isDirectory) Folder else File
			}
			if (isDirectory && includeFiles) {
				item.insertText = file + "/";
				item.command = TriggerSuggest;
			}
			items.push(item);
		}
		return items;
	}

	function createLibraryNameCompletion(range:Range, resolve:CompletionList->Void, reject:ResponseError<NoData>->Void) {
		context.languageServerProtocol.sendRequest(LanguageServerMethods.ListLibraries, null, null, function(libraries) {
			resolve({
				isIncomplete: false,
				items: libraries.map(lib -> ({
					label: lib.name,
					kind: Folder,
					textEdit: {
						newText: lib.name,
						range: range
					}
				} : CompletionItem))
			});
		}, function(_) {
			reject(ResponseError.internalError("unable to retrieve library names"));
		});
	}
}

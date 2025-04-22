package haxeLanguageServer.features.haxe.completion;

import String.fromCharCode;
import haxe.extern.EitherType;
import haxeLanguageServer.helper.TypeHelper.parseDisplayType;
import haxeLanguageServer.helper.TypeHelper.prepareSignature;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.CompletionItem;
import languageServerProtocol.Types.CompletionItemKind;
import languageServerProtocol.Types.CompletionList;
import languageServerProtocol.Types.MarkupContent;
import languageServerProtocol.Types.MarkupKind;

class CompletionFeatureLegacy {
	final context:Context;
	final contextSupport:Bool;
	final formatDocumentation:(doc:String) -> Null<EitherType<String, MarkupContent>>;

	public function new(context, contextSupport, formatDocumentation) {
		this.context = context;
		this.contextSupport = contextSupport;
		this.formatDocumentation = formatDocumentation;
	}

	public function handle(params:CompletionParams, token:CancellationToken, resolve:Null<EitherType<Array<CompletionItem>, CompletionList>>->Void,
			reject:ResponseError<NoData>->Void, doc:HxTextDocument, offset:Int, textBefore:String, _) {
		if (contextSupport && isInvalidCompletionPosition(params.context, textBefore)) {
			return resolve({items: [], isIncomplete: false});
		}
		final r = calculateCompletionPosition(textBefore, offset);
		final bytePos = context.displayOffsetConverter.characterOffsetToByteOffset(doc.content, r.pos);
		final args = ['${doc.uri.toFsPath()}@$bytePos' + (if (r.toplevel) "@toplevel" else "")];
		context.callDisplay(if (r.toplevel) "@toplevel" else "field completion", args, doc.content, token, function(result) {
			switch result {
				case DCancelled:
					resolve(null);
				case DResult(data):
					final xml = try Xml.parse(data).firstElement() catch (_:Any) null;
					if (xml == null)
						return reject.invalidXml(data);

					final items = if (r.toplevel) parseToplevelCompletion(xml, params.position, textBefore,
						doc) else parseFieldCompletion(xml, textBefore, params.position);
					resolve({items: items, isIncomplete: false});
			}
		}, reject.handler());
	}

	static final reCaseOrDefault = ~/\b(case|default)\b[^:]*:$/;

	static function isInvalidCompletionPosition(context:Null<CompletionContext>, text:String):Bool {
		return context?.triggerCharacter == ":" && reCaseOrDefault.match(text);
	}

	static final reFieldPart = ~/(\.|@(:?))(\w*)$/;

	static function calculateCompletionPosition(text:String, index:Int):CompletionPosition {
		if (reFieldPart.match(text))
			return {
				pos: index - reFieldPart.matched(3).length,
				toplevel: false,
			};

		final whitespaceAmount = text.length - text.rtrim().length;
		return {
			pos: index - whitespaceAmount,
			toplevel: true,
		};
	}

	function parseToplevelCompletion(x:Xml, position:Position, textBefore:String, doc:HxTextDocument):Array<CompletionItem> {
		final result = [];
		final timers = [];
		for (el in x.elements()) {
			@:nullSafety(Off)
			final kind:String = el.get("k");
			@:nullSafety(Off)
			final type:String = el.get("t");
			final name = el.firstChild().nodeValue;

			if (kind == "local" && name == "_") {
				continue;
			}

			final item:CompletionItem = {label: name, detail: ""};

			final displayKind = toplevelKindToCompletionItemKind(kind, type);
			if (displayKind != null)
				item.kind = displayKind;

			if (isTimerDebugFieldCompletion(name)) {
				final info = name.split(":");
				timers.push(getTimerCompletionItem(info[0], info[1], position));
				continue;
			}

			var fullName = name;
			if (kind == "global")
				fullName = el.get("p") + "." + name;
			else if (kind == "type")
				@:nullSafety(Off)
				fullName = el.get("p");

			if (type != null || fullName != name) {
				final parts = [];
				if (fullName != name)
					parts.push(fullName);
				if (type != null)
					parts.push(type); // todo format functions?
				item.detail = parts.join(" ");
			}

			final documentation = el.get("d");
			if (documentation != null)
				item.documentation = formatDocumentation(documentation);

			result.push(item);
		}
		sortTimers(timers);
		return result.concat(timers);
	}

	static function toplevelKindToCompletionItemKind(kind:String, type:String):Null<CompletionItemKind> {
		function isFunction()
			return type != null && parseDisplayType(type).match(DTFunction(_));

		return switch kind {
			case "local": if (isFunction()) Method else Variable;
			case "member" | "static": if (isFunction()) Method else Field;
			case "enum" | "enumabstract": Enum;
			case "global": Variable;
			case "type": Class;
			case "package": Module;
			case "literal": Keyword;
			case "timer": Value;
			default:
				trace("unknown toplevel item kind: " + kind);
				null;
		}
	}

	function parseFieldCompletion(x:Xml, textBefore:String, position:Position):Array<CompletionItem> {
		final result = [];
		final timers = [];
		final methods = new Map<String, {item:CompletionItem, overloads:Int}>();
		for (el in x.elements()) {
			@:nullSafety(Off)
			final rawKind:String = el.get("k");
			final kind = fieldKindToCompletionItemKind(rawKind);
			@:nullSafety(Off)
			var name:String = el.get("n");
			if (kind == Method) {
				final method = methods[name];
				if (method != null) {
					// only show an overloaded method once
					method.overloads++;
					continue;
				}
			}

			var type = null, doc = null;
			inline function getOrNull(s)
				return if (s == "") null else s;
			for (child in el.elements()) {
				switch child.nodeName {
					case "t":
						type = getOrNull(child.firstChild().nodeValue);
					case "d":
						doc = getOrNull(child.firstChild().nodeValue);
				}
			}
			var textEdit:Null<TextEdit> = null;
			if (rawKind == "metadata") {
				name = name.substr(1); // remove the @
				// if there's already a colon, don't duplicate it
				reFieldPart.match(textBefore);
				if (reFieldPart.matched(2) == ":") {
					textEdit = {newText: name, range: {start: position.translate(0, -1), end: position}};
				}
			} else if (isTimerDebugFieldCompletion(name) && type != null) {
				timers.push(getTimerCompletionItem(name, type, position));
				continue;
			}
			final item:CompletionItem = {label: name};
			if (doc != null)
				item.documentation = formatDocumentation(doc);
			if (kind != null)
				item.kind = kind;
			if (type != null)
				item.detail = formatType(type, name, kind);
			if (textEdit != null)
				item.textEdit = textEdit;

			if (kind == Method) {
				methods[name] = {item: item, overloads: 0};
			}

			result.push(item);
		}

		for (method in methods) {
			final overloads = method.overloads;
			if (overloads > 0) {
				method.item.detail += ' (+$overloads overloads)';
			}
		}

		sortTimers(timers);
		return result.concat(timers);
	}

	static function sortTimers(items:Array<CompletionItem>) {
		items.sort(function(a, b) {
			final time1:Float = cast a.data;
			final time2:Float = cast b.data;
			if (time1 < time2)
				return 1;
			if (time1 > time2)
				return -1;
			return 0;
		});

		for (i in 0...items.length) {
			items[i].sortText = "_" + fromCharCode(65 + i);
		}
	}

	static function getTimerCompletionItem(name:String, time:String, position:Position):CompletionItem {
		// avert your eyes...
		final timeRegex = ~/([0-9.]*)s(?: \(([0-9]*)%\))?/;
		var seconds = 0.0;
		var percentage = "--";
		try {
			timeRegex.match(time);
			seconds = Std.parseFloat(timeRegex.matched(1));
			percentage = timeRegex.matched(2);
		} catch (e) {}

		var doc:Null<String> = null;
		if (name.startsWith("@TIME @TOTAL")) {
			name = "@Total time: " + time;
		} else {
			name = name.replace("@TIME ", '${percentage}% ');
			doc = seconds + "s";
		}

		return {
			label: name,
			kind: Value,
			documentation: {
				kind: MarkupKind.PlainText,
				value: doc
			},
			textEdit: {
				range: {start: position, end: position},
				newText: ""
			},
			data: seconds
		};
	}

	static inline function isTimerDebugFieldCompletion(name:String):Bool {
		return name.startsWith("@TIME") || name.startsWith("@TOTAL");
	}

	static function formatType(type:String, name:String, kind:Null<CompletionItemKind>):String {
		return switch kind {
			case Method: name + prepareSignature(type);
			default: type;
		}
	}

	static function fieldKindToCompletionItemKind(kind:String):Null<CompletionItemKind> {
		return switch kind {
			case "var": Field;
			case "method": Method;
			case "type": Class;
			case "package": Module;
			case "metadata": Function;
			case "timer": Value;
			default:
				trace("unknown field item kind: " + kind);
				null;
		}
	}
}

private typedef CompletionPosition = {
	final pos:Int;
	final toplevel:Bool;
}

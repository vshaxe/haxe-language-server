package haxeLanguageServer.features.haxe;

import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.protocol.ColorProvider.ColorPresentationParams;
import languageServerProtocol.protocol.ColorProvider.ColorPresentationRequest;
import languageServerProtocol.protocol.ColorProvider.DocumentColorParams;
import languageServerProtocol.protocol.ColorProvider.DocumentColorRequest;

class ColorProviderFeature {
	final context:Context;
	final computer:ColorComputer;
	final upperCaseHexRegex = ~/0x([A-F0-9]{6})/g;

	public function new(context) {
		this.context = context;
		computer = new ColorComputer();
		context.languageServerProtocol.onRequest(DocumentColorRequest.type, onDocumentColor);
		context.languageServerProtocol.onRequest(ColorPresentationRequest.type, onColorPresentation);
	}

	function onDocumentColor(params:DocumentColorParams, token:CancellationToken, resolve:Array<ColorInformation>->Void, reject:ResponseError<NoData>->Void) {
		final onResolve = context.startTimer("haxe/documentColor");
		final uri = params.textDocument.uri;
		final doc = context.documents.getHaxe(uri);
		if (doc == null) {
			return reject.noFittingDocument(uri);
		}
		final colors:Array<ColorInformation> = computer.compute(doc);
		resolve(colors);
		onResolve(null, colors.length + " colors");
	}

	function onColorPresentation(params:ColorPresentationParams, token:CancellationToken, resolve:Array<ColorPresentation>->Void,
			reject:ResponseError<NoData>->Void) {
		final onResolve = context.startTimer("haxe/colorPresentation");
		final uri = params.textDocument.uri;
		final doc = context.documents.getHaxe(uri);
		if (doc == null) {
			return reject.noFittingDocument(uri);
		}
		var hex = toHexColor(Math.round(params.color.alpha * 255), Math.round(params.color.red * 255), Math.round(params.color.green * 255),
			Math.round(params.color.blue * 255));
		final size = params.range.end.character - params.range.start.character;
		// do not add alpha to 0xRRGGBB if alpha has not changed
		if (size == 6 + 2 && params.color.alpha == 1) {
			hex = hex.substr(2);
		}
		final originalText = doc.getText(params.range);
		if (!upperCaseHexRegex.match(originalText)) {
			hex = hex.toLowerCase();
		}
		final color:ColorPresentation = {
			label: '0x${hex}',
			textEdit: {
				range: params.range,
				newText: '0x${hex}',
			}
		};

		final colors = [color];
		resolve(colors);
		onResolve(null, colors.length + " color presentations");
	}

	function toHexColor(a:Float, r:Float, g:Float, b:Float):String {
		a = clamp(a, 0, 255);
		r = clamp(r, 0, 255);
		g = clamp(g, 0, 255);
		b = clamp(b, 0, 255);
		return '${asHex(a)}${asHex(r)}${asHex(g)}${asHex(b)}';
	}

	function asHex(v:Float):String {
		return StringTools.hex(Math.round(v), 2);
	}

	function clamp(v:Float, min:Float, max:Float):Float {
		return Math.min(Math.max(min, v), max);
	}
}

private class ColorComputer {
	final argbHexRegex = ~/0x([A-Fa-f0-9]{8})(\W|$)/g;
	final rgbHexRegex = ~/0x([A-Fa-f0-9]{6})(\W|$)/g;

	public function new() {}

	public function compute(document:HaxeDocument):Array<ColorInformation> {
		var text = document.getText();
		final colors:Array<ColorInformation> = [];

		text = argbHexRegex.map(text, r -> {
			final color = fromArgb(r.matched(1));
			final p = r.matchedPos();
			colors.push({
				range: toRange(document, p.pos, p.len - 1),
				color: color
			});
			// replace to random value with same length
			return "0xAARRGGBB" + r.matched(2);
		});
		text = rgbHexRegex.map(text, r -> {
			final color = fromRgb(r.matched(1));
			final p = r.matchedPos();
			colors.push({
				range: toRange(document, p.pos, p.len - 1),
				color: color
			});
			return "0xRRGGBB" + r.matched(2);
		});

		return colors;
	}

	function toRange(document:HaxeDocument, offset:Int, length:Int):Range {
		return {
			start: document.positionAt(offset),
			end: document.positionAt(offset + length)
		};
	}

	function fromArgb(input:String):Color {
		final a = (Std.parseInt("0x" + input.substr(0, 2)) ?? 255) / 255;
		final r = (Std.parseInt("0x" + input.substr(2, 2)) ?? 255) / 255;
		final g = (Std.parseInt("0x" + input.substr(4, 2)) ?? 255) / 255;
		final b = (Std.parseInt("0x" + input.substr(6, 2)) ?? 255) / 255;
		return {
			red: r,
			green: g,
			blue: b,
			alpha: a
		};
	}

	function fromRgb(input:String):Color {
		final r = (Std.parseInt("0x" + input.substr(0, 2)) ?? 255) / 255;
		final g = (Std.parseInt("0x" + input.substr(2, 2)) ?? 255) / 255;
		final b = (Std.parseInt("0x" + input.substr(4, 2)) ?? 255) / 255;
		return {
			red: r,
			green: g,
			blue: b,
			alpha: 1
		};
	}
}

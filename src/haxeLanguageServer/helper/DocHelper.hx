package haxeLanguageServer.helper;

class DocHelper {
	static final reStartsWhitespace = ~/^\s*/;
	static final reEndsWithWhitespace = ~/\s*$/;

	/** Stolen from dox **/
	public static function trim(doc:String) {
		if (doc == null)
			return '';

		// trim leading asterisks
		while (doc.charAt(0) == '*')
			doc = doc.substr(1);

		// trim trailing asterisks
		while (doc.charAt(doc.length - 1) == '*')
			doc = doc.substr(0, doc.length - 1);

		// trim additional whitespace
		doc = doc.trim();

		// detect doc comment style/indent
		final ereg = ~/^([ \t]+(\* )?)[^\s\*]/m;
		final matched = ereg.match(doc);

		if (matched) {
			var string = ereg.matched(1);

			// escape asterisk and allow one optional space after it
			string = string.split('* ').join('\\* ?');

			final indent = new EReg("^" + string, "gm");
			doc = indent.replace(doc, "");
		}

		// TODO: check why this is necessary (dox doesn't seem to need it...)
		if (doc.charAt(0) == '*')
			doc = doc.substr(1).ltrim();

		return doc;
	}

	public static function markdownFormat(doc:String):String {
		function tableLine(a, b)
			return '| $a | $b |\n';
		function tableHeader(a, b)
			return "\n" + tableLine(a, b) + tableLine("------", "------");
		function replaceNewlines(s:String, by:String)
			return s.replace("\n", by).replace("\r", by);
		function mapDocTags(tags)
			return tags.map(function(p) {
				final desc = replaceNewlines(p.doc, " ");
				return tableLine("`" + p.value + "`", desc);
			}).join("");

		doc = trim(doc);
		final docInfos = JavadocHelper.parse(doc);
		var result = docInfos.doc;
		final hasParams = docInfos.params.length > 0;
		final hasReturn = docInfos.returns != null;

		result += "\n";

		if (docInfos.deprecated != null)
			result += "\n**Deprecated:** " + docInfos.deprecated.doc + "\n";

		if (hasParams || hasReturn)
			result += tableHeader("Argument", "Description");
		if (hasParams)
			result += mapDocTags(docInfos.params);
		if (hasReturn)
			result += tableLine("`return`", replaceNewlines(docInfos.returns.doc, " "));

		if (docInfos.throws.length > 0)
			result += tableHeader("Exception", "Description") + mapDocTags(docInfos.throws);

		if (docInfos.events.length > 0)
			result += tableHeader("Event", "Description") + mapDocTags(docInfos.events);

		if (docInfos.sees.length > 0)
			result += "\nSee also:\n" + docInfos.sees.map(function(p) return "* " + p.doc).join("\n") + "\n";

		if (docInfos.since != null)
			result += '\n_Available since ${docInfos.since.doc}_';

		return result;
	}

	public static function extractText(doc:String):String {
		if (doc == null)
			return null;

		var result = "";
		for (line in doc.trim().split("\n")) {
			line = line.trim();
			if (line.startsWith("*")) // JavaDoc-style comments
				line = line.substr(1);

			if (line == "")
				result += "\n\n";
			else
				result += line + " ";
		}
		return result;
	}

	public static function printCodeBlock(content:String, languageId:LanguageId):String {
		return '```$languageId\n$content\n```';
	}

	/**
		expands range to encompass full lines when range has leading or trailing whitespace in first and / or last line

		@param doc referenced document
		@param range selected range inside document
	**/
	public static function untrimRange(doc:TextDocument, range:Range) {
		final startLine = doc.lineAt(range.start.line);
		if (reStartsWhitespace.match(startLine.substring(0, range.start.character)))
			range = {
				start: {
					line: range.start.line,
					character: 0
				},
				end: range.end
			};

		final endLine = if (range.start.line == range.end.line) startLine else doc.lineAt(range.end.line);
		if (reEndsWithWhitespace.match(endLine.substring(range.end.character)))
			range = {
				start: range.start,
				end: {
					line: range.end.line + 1,
					character: 0
				}
			};
		return range;
	}
}

enum abstract LanguageId(String) to String {
	final Haxe = "haxe";
	final HaxeType = "haxe.type";
	final HaxeArgument = "haxe.argument";
	final Hxml = "hxml";
}

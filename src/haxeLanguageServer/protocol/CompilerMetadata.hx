package haxeLanguageServer.protocol;

enum abstract CompilerMetadata(String) to String {
	final Op = ":op";
	final Resolve = ":resolve";
	final ArrayAccess = ":arrayAccess";
	final Final = ":final";
	final Optional = ":optional";
	final Enum = ":enum";
	final Value = ":value";
	final Deprecated = ":deprecated";
	final NoCompletion = ":noCompletion";
	final Overload = ":overload";
}

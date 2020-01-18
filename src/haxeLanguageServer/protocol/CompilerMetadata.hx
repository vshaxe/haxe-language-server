package haxeLanguageServer.protocol;

enum abstract CompilerMetadata(String) to String {
	var Op = ":op";
	var Resolve = ":resolve";
	var ArrayAccess = ":arrayAccess";
	var Final = ":final";
	var Optional = ":optional";
	var Enum = ":enum";
	var Value = ":value";
	var Deprecated = ":deprecated";
	var NoCompletion = ":noCompletion";
	// TODO
}

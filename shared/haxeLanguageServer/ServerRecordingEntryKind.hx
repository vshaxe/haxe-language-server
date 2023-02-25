package haxeLanguageServer;

enum abstract ServerRecordingEntryKind(String) to String {
	var In = "<";
	var Out = ">";
	var Local = "-";
	var Comment = "#";
}

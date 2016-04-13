import haxe.extern.EitherType;

typedef Position = {
    var line:Int;
    var character:Int;
}

typedef Range = {
    var start:Position;
    var end:Position;
}

typedef Location = {
    var uri:String;
    var range:Range;
}

typedef Diagnostic = {
    var range:Range;
    @:optional var severity:DiagnosticSeverity;
    @:optional var code:EitherType<Int,String>;
    @:optional var source:String;
    var message:String;
}

@:enum abstract DiagnosticSeverity(Int) {
    var Error = 1;
    var Warning = 2;
    var Information = 3;
    var Hint = 4;
}

typedef Command  ={
    var title:String;
    var command:String;
    @:optional var arguments:Array<Dynamic>;
}

typedef TextEdit = {
    var range:Range;
    var newText:String;
}

typedef WorkspaceEdit = {
    var changes:haxe.DynamicAccess<Array<TextEdit>>;
}

typedef TextDocumentIdentifier = {
    var uri:String;
}

typedef TextDocumentItem = {
    var uri:String;
    var languageId:String;
    var version:Int;
    var text:String;
}

typedef VersionedTextDocumentIdentifier = {
    >TextDocumentIdentifier,
    var version:Int;
}

typedef TextDocumentPositionParams = {
    var textDocument:TextDocumentIdentifier;
    var position:Position;
}

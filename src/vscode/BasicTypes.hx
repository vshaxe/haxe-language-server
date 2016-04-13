/*
    This module contains basic types used when working with VSCode language server protocol.
*/
package vscode;

/**
    Position in a text document expressed as zero-based line and character offset.
**/
typedef Position = {
    /**
        Line position in a document (zero-based).
    **/
    var line:Int;

    /**
        Character offset on a line in a document (zero-based).
    **/
    var character:Int;
}

/**
    A range in a text document expressed as (zero-based) start and end positions.
**/
typedef Range = {
    /**
        The range's start position
    **/
    var start:Position;

    /**
        The range's end position
    **/
    var end:Position;
}

/**
    Represents a location inside a resource, such as a line inside a text file.
**/
typedef Location = {
    var uri:String;
    var range:Range;
}

/**
    Represents a diagnostic, such as a compiler error or warning.
    Diagnostic objects are only valid in the scope of a resource.
**/
typedef Diagnostic = {
    /**
        The range at which the message applies
    **/
    var range:Range;

    /**
        The diagnostic's severity.
        If omitted it is up to the client to interpret diagnostics as error, warning, info or hint.
    **/
    @:optional var severity:DiagnosticSeverity;

    /**
        The diagnostic's code.
    **/
    @:optional var code:haxe.extern.EitherType<Int,String>;

    /**
        A human-readable string describing the source of this diagnostic, e.g. 'typescript' or 'super lint'.
    **/
    @:optional var source:String;

    /**
        The diagnostic's message.
    **/
    var message:String;
}

@:enum abstract DiagnosticSeverity(Int) {
    var Error = 1;
    var Warning = 2;
    var Information = 3;
    var Hint = 4;
}

/**
    Represents a reference to a command.
    Provides a title which will be used to represent a command in the UI and,
    optionally, an array of arguments which will be passed to the command handler function when invoked.
**/
typedef Command  ={
    /**
        Title of the command, like `save`.
    **/
    var title:String;

    /**
        The identifier of the actual command handler.
    **/
    var command:String;

    /**
        Arguments that the command handler should be invoked with.
    **/
    @:optional var arguments:Array<Dynamic>;
}

/**
    A textual edit applicable to a text document.
**/
typedef TextEdit = {
    /**
        The range of the text document to be manipulated.
        To insert text into a document create a range where start == end.
    **/
    var range:Range;

    /**
        The string to be inserted.
        For delete operations use an empty string.
    **/
    var newText:String;
}

/**
    A workspace edit represents changes to many resources managed in the workspace.
**/
typedef WorkspaceEdit = {
    /**
        Holds changes to existing resources.
    **/
    var changes:haxe.DynamicAccess<Array<TextEdit>>;
}

/**
    Text documents are identified using an URI.
    On the protocol level URI's are passed as strings.
**/
typedef TextDocumentIdentifier = {
    /**
        The text document's uri.
    **/
    var uri:String;
}

/**
    An item to transfer a text document from the client to the server.
**/
typedef TextDocumentItem = {
    /**
        The text document's uri.
    **/
    var uri:String;

    /**
        The text document's language identifier.
    **/
    var languageId:String;

    /**
        The version number of this document (it will strictly increase after each change, including undo/redo).
    **/
    var version:Int;

    /**
        The content of the opened text document.
    **/
    var text:String;
}

/**
    An identifier to denote a specific version of a text document.
**/
typedef VersionedTextDocumentIdentifier = {
    >TextDocumentIdentifier,

    /**
        The version number of this document.
    **/
    var version:Int;
}

/**
    A parameter literal used in requests to pass a text document and a position inside that document.
**/
typedef TextDocumentPositionParams = {
    /**
        The text document.
    **/
    var textDocument:TextDocumentIdentifier;

    /**
        The position inside the text document.
    **/
    var position:Position;
}

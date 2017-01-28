package haxeLanguageServer;

abstract ApplyFixesCommand(Command) to Command {
    public function new(title:String, params:{textDocument:TextDocumentIdentifier}, edits:Array<TextEdit>) {
        this = {
            title: title,
            command: "haxe.applyFixes",
            arguments: [params.textDocument.uri, 0, edits]
        }
    }

    @:to function toArray():Array<Command> {
        return [this];
    }
}
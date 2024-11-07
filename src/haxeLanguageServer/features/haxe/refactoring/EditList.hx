package haxeLanguageServer.features.haxe.refactoring;

import haxe.extern.EitherType;
import languageServerProtocol.Types.CreateFile;
import languageServerProtocol.Types.DeleteFile;
import languageServerProtocol.Types.RenameFile;
import languageServerProtocol.Types.TextDocumentEdit;

using Lambda;
using haxeLanguageServer.helper.PathHelper;

class EditList {
	public var documentChanges:Array<EitherType<TextDocumentEdit, EitherType<CreateFile, EitherType<RenameFile, DeleteFile>>>>;

	public function new() {
		documentChanges = [];
	}

	public function addEdit(edit:EitherType<TextDocumentEdit, EitherType<CreateFile, EitherType<RenameFile, DeleteFile>>>) {
		documentChanges.push(edit);
	}
}

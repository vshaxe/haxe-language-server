package haxeLanguageServer.helper;

import haxe.extern.EitherType;

/**
	A copy of the LSP completion type where `textEdit` is not optional to deal with some null safety annoyances.
**/
typedef TextEditCompletionItem = {
	/**
		The label of this completion item.
		By default also the text that is inserted when selecting this completion.
	**/
	var label:String;

	/**
		The kind of this completion item.
		Based of the kind an icon is chosen by the editor.
	**/
	var ?kind:CompletionItemKind;

	/**
		Tags for this completion item.

		@since 3.15.0
	**/
	var ?tags:Array<CompletionItemTag>;

	/**
		A human-readable string with additional information about this item, like type or symbol information.
	**/
	var ?detail:String;

	/**
		A human-readable string that represents a doc-comment.
	**/
	var ?documentation:EitherType<String, MarkupContent>;

	/**
		Indicates if this item is deprecated.
		@deprecated Use `tags` instead.
	**/
	var ?deprecated:Bool;

	/**
		Select this item when showing.

		*Note* that only one completion item can be selected and that the
		tool / client decides which item that is. The rule is that the *first*
		item of those that match best is selected.
	**/
	var ?preselect:Bool;

	/**
		A string that should be used when comparing this item with other items.
		When `falsy` the label is used.
	**/
	var ?sortText:String;

	/**
		A string that should be used when filtering a set of completion items.
		When `falsy` the label is used.
	**/
	var ?filterText:String;

	/**
		A string that should be inserted into a document when selecting
		this completion. When `falsy` the [label](#CompletionItem.label)
		is used.

		The `insertText` is subject to interpretation by the client side.
		Some tools might not take the string literally. For example
		VS Code when code complete is requested in this example `con<cursor position>`
		and a completion item with an `insertText` of `console` is provided it
		will only insert `sole`. Therefore it is recommended to use `textEdit` instead
		since it avoids additional client side interpretation.
	**/
	var ?insertText:String;

	/**
		The format of the insert text. The format applies to both the `insertText` property
		and the `newText` property of a provided `textEdit`. If ommitted defaults to
		`InsertTextFormat.PlainText`.
	**/
	var ?insertTextFormat:InsertTextFormat;

	/**
		A `TextEdit` which is applied to a document when selecting
		this completion. When an edit is provided the value of
		`insertText` is ignored.

		*Note:* The text edit's range must be a [single line] and it must contain the position
		at which completion has been requested.
	**/
	var textEdit:TextEdit;

	/**
		An optional array of additional [text edits](#TextEdit) that are applied when
		selecting this completion. Edits must not overlap (including the same insert position)
		with the main [edit](#CompletionItem.textEdit) nor with themselves.

		Additional text edits should be used to change text unrelated to the current cursor position
		(for example adding an import statement at the top of the file if the completion item will
		insert an unqualified type).
	**/
	var ?additionalTextEdits:Array<TextEdit>;

	/**
		An optional set of characters that when pressed while this completion is active will accept it first and
		then type that character. *Note* that all commit characters should have `length=1` and that superfluous
		characters will be ignored.
	**/
	var ?commitCharacters:Array<String>;

	/**
		An optional command that is executed *after* inserting this completion. *Note* that
		additional modifications to the current document should be described with the
		additionalTextEdits-property.
	**/
	var ?command:Command;

	/**
		An data entry field that is preserved on a completion item between a completion and a completion resolve request.
	**/
	var ?data:Dynamic;
}

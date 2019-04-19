package haxeLanguageServer.tokentree;

enum TokenContext {
	/** we're at root level **/
	Root(pos:RootPosition);

	/** we're in a type **/
	Type(type:TypeContextData);
}

enum RootPosition {
	BeforePackage;
	BeforeFirstImport;
	BeforeFirstType;
	AfterFirstType;
}

typedef TypeContextData = {
	final kind:TypeKind;
	final ?field:{
		final isStatic:Bool;
		final kind:FieldKind;
	};
}

enum TypeKind {
	Class;
	Interface;
	Enum;
	EnumAbstract;
	Abstract;
	Typedef;
	MacroClass; // TODO: add argument for the containing type's context?
}

enum FieldKind {
	Var;
	Final;
	Function;
}

package haxeLanguageServer.tokentree;

enum TokenContext {
	/** we're at root level **/
	Root(pos:RootPosition);

	/** we're in a type **/
	Type(type:TypeContext);

	/** we're in a module-level field **/
	ModuleLevelStatic(kind:FieldKind);
}

enum RootPosition {
	BeforePackage;
	BeforeFirstImport;
	BeforeFirstType;
	AfterFirstType;
}

typedef TypeContext = {
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

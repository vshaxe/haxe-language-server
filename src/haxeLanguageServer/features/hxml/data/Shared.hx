package haxeLanguageServer.features.hxml.data;

typedef EnumValue = {
	final name:String;
	final ?description:String;
}

typedef EnumValues = ReadOnlyArray<EnumValue>;

final DceEnumValues:EnumValues = [
	{
		name: "full",
		description: "Apply dead code elimination to all code."
	},
	{
		name: "std",
		description: "Only apply dead code elimination to the standard library."
	},
	{
		name: "no",
		description: "Disable dead code elimination."
	}
];

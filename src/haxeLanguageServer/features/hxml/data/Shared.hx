package haxeLanguageServer.features.hxml.data;

import haxe.ds.ReadOnlyArray;

typedef EnumValue = {
	final name:String;
	final ?description:String;
}

typedef EnumValues = ReadOnlyArray<EnumValue>;

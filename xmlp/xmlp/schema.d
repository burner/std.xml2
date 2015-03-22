module xmlp.schema.types;

import std.variant;
/** built in simple types and their facets */





/** each of this has facets that can restrict the range of values of a derived type */
/+
immutable string[] BuiltinTypeNames = [
	"string",
	"normalizedString",
	"token",
	"base64Binary",
	"hexBinary",
	"integer",
	"positiveInteger",
	"negativeInteger",
	"nonNegativeInteger",
	"nonPositiveInteger",
	"long", "unsignedLong",
	"int", "unsignedInt",
	"short", "unsignedShort",
	"byte", "unsignedByte",
	"decimal", "float", "double",
	"boolean",
	"dateTime", "date", "time",
	"gYear", "gYearMonth", "gMonth", "gMonthDay", "gDay",
	"Name", "QName", "NCNAme",
	"anyURI",
	"language",
	"ID","IDREF","IDREFS","ENTITY", "ENTITIES","NOTATION","NMTOKEN", "NMTOKENS"
];
+/
immutable string[] FacetNames = [
	"length",
	"minLength",
	"maxLength",
	"pattern",
	"enumeration",
	"whiteSpace",
	"maxInclusive",
	"maxExclusive",
	"minInclusive",
	"minExclusive",
	"totalDigits",
	"fractionDigits"
];


enum FacetFlag {
	Length = 1,
	MinLength = 2,
	MaxLength = 4,
	Pattern = 8,
	Enumeration = 16,
	WhiteSpace = 32,
	MaxInclude = 64,
	MaxExlude = 128,
	MinInclude = 256,
	MinExclude = 512,
	TotalDigits = 1024,
	FractionDigits = 2048,
	BooleanFacets = Pattern+WhiteSpace,
	StringFacets = Length+MinLength+MaxLength+Pattern+Enumeration+WhiteSpace,
	IntegerFacets = Pattern+Enumeration+WhiteSpace+MaxInclude+MaxExlude+MinInclude+MinExclude+TotalDigits+FractionDigits,
	NumberFacets = Pattern+Enumeration+WhiteSpace+MaxInclude+MaxExlude+MinInclude+MinExclude
	
}

class FacetData {
	FacetFlag id;
	Variant	  value;		
}

class TypeBase {
	string		name;
	string		nsURI; // target namespace	
	string		baseType;
}

class AnySimpleType : TypeBase {
	FacetFlag	baseFacets;
	FacetFlag	restrictFacets;
	FacetData[]	restrict;
}

class SimpleType : AnySimpleType {
	
	this(string stname, FacetFlag allowed)
	{
		name = stname;
		baseFacets = allowed;
		gSimpleTypes[stname] = this;
	}
}

class SimpleTypeRestriction {
	FacetFlag	flag;
	bool		fixed;
	Variant		value;
};

alias SimpleType[string] SimpleTypeMap;
alias FacetFlag[string]	 FacetFlagMap;

__gshared	SimpleTypeMap gSimpleTypes;


class XSDAttribute {
	string name;
}

class XSDElement {
	string name;
	
}
static this()
{
	new SimpleType("string", FacetFlag.StringFacets);
	new SimpleType("normalizedString", FacetFlag.StringFacets);
	new SimpleType("token", FacetFlag.StringFacets);
	new SimpleType("base64Binary", FacetFlag.StringFacets);
	new SimpleType("hexBinary", FacetFlag.StringFacets);
	new SimpleType("integer",FacetFlag.IntegerFacets);
	new SimpleType("positiveInteger",FacetFlag.IntegerFacets);
	new SimpleType("negativeInteger",FacetFlag.IntegerFacets);
	new SimpleType("nonNegativeInteger",FacetFlag.IntegerFacets);
	new SimpleType("nonPositiveInteger",FacetFlag.IntegerFacets);
	new SimpleType("long",FacetFlag.IntegerFacets);
	new SimpleType("unsignedLong",FacetFlag.IntegerFacets);
	new SimpleType("int",FacetFlag.IntegerFacets);
	new SimpleType("unsignedInt",FacetFlag.IntegerFacets);
	new SimpleType("short",FacetFlag.IntegerFacets);
	new SimpleType("unsignedShort",FacetFlag.IntegerFacets);
	new SimpleType("byte",FacetFlag.IntegerFacets);
	new SimpleType("unsignedByte",FacetFlag.IntegerFacets);
	new SimpleType("decimal", FacetFlag.IntegerFacets);
	new SimpleType("float", FacetFlag.NumberFacets);
	new SimpleType("double", FacetFlag.NumberFacets);
	new SimpleType("boolean", FacetFlag.BooleanFacets);
	
	new SimpleType("dateTime", FacetFlag.NumberFacets);
	new SimpleType("date", FacetFlag.NumberFacets);
	new SimpleType("time", FacetFlag.NumberFacets);
	new SimpleType("gYear", FacetFlag.NumberFacets);
	new SimpleType("gYearMonth", FacetFlag.NumberFacets);
	new SimpleType("gMonth", FacetFlag.NumberFacets);
	new SimpleType("gMonthDay", FacetFlag.NumberFacets);
	new SimpleType("gDay", FacetFlag.NumberFacets);

	new SimpleType("Name", FacetFlag.StringFacets);
	new SimpleType("QName", FacetFlag.StringFacets);
	new SimpleType("NCNAme", FacetFlag.StringFacets);
	new SimpleType("anyURI", FacetFlag.StringFacets);
	new SimpleType("language", FacetFlag.StringFacets);
	new SimpleType("ID", FacetFlag.StringFacets);
	new SimpleType("IDREF", FacetFlag.StringFacets);
	new SimpleType("IDREFS", FacetFlag.StringFacets);
	new SimpleType("ENTITY", FacetFlag.StringFacets);
	new SimpleType("ENTITIES", FacetFlag.StringFacets);
	new SimpleType("NOTATION", FacetFlag.StringFacets);
	new SimpleType("NMTOKEN", FacetFlag.StringFacets);
	new SimpleType("NMTOKENS", FacetFlag.StringFacets);

	
}


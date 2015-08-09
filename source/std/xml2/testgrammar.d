module std.xml2.testgrammar;

import std.xml2.testing : XmlGen, XmlGenSeq, XmlGenOr, XmlGenString,
	   XmlGenLiteral, XmlGenStar, XmlGenChar, XmlGenCharRange;

import std.experimental.logger;

/* The '+' grammar symbol will be translated as 1,2.
The '*' grammar symbol will be translated as 0,1,2.
The '?' grammar symbol will be translated as 0,1.
*/

class XmlGenGenerator {
	this() {
		// [ 3] S ::= (#x20 | #x9 | #xD | #xA)+
		S = //new XmlGenStar(
			new XmlGenOr([
				new XmlGenLiteral(" "),	
				new XmlGenLiteral("\n"),	
				new XmlGenLiteral("\t")
			])//, 1, 3
		//)
		;

		// [ 4] NameStartChar ::= ":" | [A-Z] | "_" | [a-z] | [#xC0-#xD6]
		NameStartChar = new XmlGenOr([ new XmlGenLiteral(":"), 
			new XmlGenLiteral(":"), new XmlGenCharRange('A', 'Z'),
			new XmlGenCharRange('A', 'Z') //, new XmlGenCharRange('\xC0', '\xD6')
		]);

		/* [4a] NameChar ::= NameStartChar |  "-" | "." | [0-9] | #xB7 |
				[#x0300-#x036F] | [#x203F-#x2040]
		*/
		NameChar = new XmlGenOr([NameStartChar.save, new XmlGenLiteral("-"),
			new XmlGenLiteral("."), new XmlGenCharRange('0', '9')
		]);

		// [ 5] Name ::= NameStartChar (NameChar)*
		Name = new XmlGenSeq([NameStartChar.save, 
			new XmlGenStar(NameChar.save, 1, 3)
		]);

		// [ 7] Nmtoken ::= (NameChar)+
		Nmtoken = new XmlGenStar(NameChar, 1, 3);

		// [11] SystemLiteral ::= ('"' [^"]* '"') | ("'" [^']* "'")
		SystemLiteral = new XmlGenOr([
			new XmlGenSeq([ 
				new XmlGenLiteral("\""),
				new XmlGenOr([new XmlGenChar(), new XmlGenCharRange('<', '>')]),
				new XmlGenLiteral("\"")
			]),
			new XmlGenSeq([ 
				new XmlGenLiteral("'"),
				new XmlGenOr([new XmlGenChar("'"), new XmlGenCharRange('<', '>')]),
				new XmlGenLiteral("'")
			]),
		]);
		
		// [25] Eq ::= S? '=' S?
		Eq = new XmlGenSeq([ new XmlGenStar(S.save, 0, 2), 
			new XmlGenLiteral("="), S.save 
		]);

		// [26] VersionNum ::= '1.' [0-9]+
		VersionNum = new XmlGenSeq([ 
			new XmlGenLiteral("1."),
			new XmlGenStar(new XmlGenCharRange('0','9'), 1,3)
		]);

		/* [24] VersionInfo ::= S 'version' Eq ("'" VersionNum "'" |
				'"' VersionNum '"')
		*/
		VersionInfo = new XmlGenSeq([ S.save, new XmlGenLiteral("version"),
			Eq.save,
			new XmlGenOr([
				new XmlGenSeq([new XmlGenLiteral("'"), VersionNum.save, 
					new XmlGenLiteral("'")
				]),
				new XmlGenSeq([new XmlGenLiteral("\""), VersionNum.save, 
					new XmlGenLiteral("\"")
				]),
			])
		]);

		/* [66] CharRef ::= '&#' [0-9]+ ';'
						| '&#x' [0-9a-fA-F]+ ';'
		*/
		CharRef = new XmlGenOr([
			new XmlGenSeq([
				new XmlGenLiteral("&#"),
				new XmlGenStar(new XmlGenCharRange('0','9'), 1, 3),
				new XmlGenLiteral(";")
			]),
			new XmlGenSeq([
				new XmlGenLiteral("&#x"),
				new XmlGenStar(
					new XmlGenOr([
						new XmlGenCharRange('0','9'),
						new XmlGenCharRange('a','f'),
						new XmlGenCharRange('A','F')
					]), 1, 3
				),
				new XmlGenLiteral(";")
			]),
		]);

		// [68] EntityRef ::= '&' Name ';'
		EntityRef = new XmlGenSeq([
			new XmlGenLiteral("&"),
			Name.save,
			new XmlGenLiteral(";"),
		]);

		// [67] Reference ::= EntityRef | CharRef
		Reference = new XmlGenOr([EntityRef.save, CharRef.save]);

		// [69] PEReference ::= '%' Name ';'
		PEReference = new XmlGenSeq([
			new XmlGenLiteral("%"),
			Name.save,
			new XmlGenLiteral(";"),
		]);

		/* [ 9] EntityValue ::= '"' ([^%&"] | PEReference | Reference)* '"'
							|  "'" ([^%&'] | PEReference | Reference)* "'"
		*/
		EntityValue = new XmlGenOr([
			new XmlGenSeq([ 
				new XmlGenLiteral("\""), 
				new XmlGenStar(
					new XmlGenOr([
						new XmlGenChar("%&\""),
						PEReference.save,
						Reference.save
					]) , 0, 3
				),
				new XmlGenLiteral("\""), 
			]),
			new XmlGenSeq([ 
				new XmlGenLiteral("'"), 
				new XmlGenStar(
					new XmlGenOr([
						new XmlGenChar("%&'"),
						PEReference.save,
						Reference.save
					]) , 0, 3
				),
				new XmlGenLiteral("'"), 
			])
		]);

		/* [10] AttValue ::= '"' ([^<&"] | Reference)* '"'
						|  "'" ([^<&'] | Reference)* "'"
		*/
		AttValue = new XmlGenOr([
			new XmlGenSeq([ 
				new XmlGenLiteral("\""), 
				new XmlGenStar(
					new XmlGenOr([
						new XmlGenChar("<&\""),
						Reference.save
					]) , 0, 3
				),
				new XmlGenLiteral("\""), 
			]),
			new XmlGenSeq([ 
				new XmlGenLiteral("'"), 
				new XmlGenStar(
					new XmlGenOr([
						new XmlGenChar("<&'"),
						Reference.save
					]) , 0, 3
				),
				new XmlGenLiteral("'"), 
			])
		]);

		/* [13] PubidChar ::= #x20 | #xD | #xA | [a-zA-Z0-9] 
						| [-'()+,./:=?;!*#@$_%]
		*/
		PubidChar = new XmlGenChar();

		// [12] PubidLiteral ::= '"' PubidChar* '"' | "'" (PubidChar - "'")* "'"
		PubidLiteral = new XmlGenOr([
			new XmlGenSeq([ 
				new XmlGenLiteral("\""), 
				new XmlGenStar(PubidChar.save, 0, 3),
				new XmlGenLiteral("\""), 
			]),
			new XmlGenSeq([ 
				new XmlGenLiteral("'"), 
				new XmlGenStar(new XmlGenChar("-"), 0, 3),
				new XmlGenLiteral("'"), 
			]),
		]);

		// [49]	choice ::= '(' S? cp ( S? '|' S? cp )+ S? ')'
		// [48]	cp ::= (Name | choice | seq) ('?' | '*' | '+')?
		// [50]	seq ::= '(' S? cp ( S? ',' S? cp )* S? ')'
		// [47]	children ::= (choice | seq) ('?' | '*' | '+')?

		// [55]	StringType ::= 'CDATA'
		StringType = new XmlGenLiteral("CDATA");

		/* [56]	TokenizedType ::= 'ID'
								| 'IDREF'
								| 'IDREFS'
								| 'ENTITY'
								| 'ENTITIES'
								| 'NMTOKEN'
								| 'NMTOKENS'
		*/
		TokenizedType = new XmlGenOr([
			new XmlGenLiteral("ID"),
			new XmlGenLiteral("IDREF"),
			new XmlGenLiteral("IDREFS"),
			new XmlGenLiteral("ENTITY"),
			new XmlGenLiteral("ENTITIES"),
			new XmlGenLiteral("NMTOKEN"),
			new XmlGenLiteral("NMTOKENS")
		]);

		/* [51] Mixed ::= '(' S? '#PCDATA' (S? '|' S? Name)* S? ')*'
						| '(' S? '#PCDATA' S? ')'
		*/
		Mixed = new XmlGenOr([
			new XmlGenSeq([
				new XmlGenLiteral("("), 
				new XmlGenStar(S.save, 0, 2),
				new XmlGenLiteral("#PCDATA"), 
				new XmlGenStar(
					new XmlGenOr([
						new XmlGenStar(S.save, 0, 2),
						new XmlGenSeq([
							new XmlGenStar(S.save, 0, 2),
							Name.save
						])
					]), 0, 3
				),
				new XmlGenStar(S.save, 0, 2),
				new XmlGenLiteral(")*"), 
			]),
			new XmlGenSeq([
				new XmlGenLiteral("("), 
				new XmlGenStar(S.save, 0, 2),
				new XmlGenLiteral("#PCDATA"), 
				new XmlGenStar(S.save, 0, 2),
				new XmlGenLiteral(")"), 
			])
		]);

		// [59]	Enumeration ::= '(' S? Nmtoken (S? '|' S? Nmtoken)* S? ')'
		Enumeration = new XmlGenSeq([
			new XmlGenLiteral("("), 
			new XmlGenStar(S.save, 0, 2),
			Nmtoken.save,
			new XmlGenStar(
				new XmlGenOr([
					new XmlGenStar(S.save, 0, 2),
					new XmlGenSeq([
						new XmlGenStar(S.save, 0, 2),
						Nmtoken.save
					])
				]), 0, 3
			),
			new XmlGenStar(S.save, 0, 2),
			new XmlGenLiteral(")"), 
		]);

		// [58]	NotationType ::= 'NOTATION' S '(' S? Name (S? '|' S?  Name)* S? ')'
		NotationType = new XmlGenSeq([
			new XmlGenLiteral("NOTATION"), 
			S.save,
			new XmlGenLiteral("("), 
			new XmlGenStar(S.save, 0, 2),
			Name.save,
			new XmlGenStar(
				new XmlGenOr([
					new XmlGenStar(S.save, 0, 2),
					new XmlGenSeq([
						new XmlGenStar(S.save, 0, 2),
						Name.save
					])
				]), 0, 3
			),
			new XmlGenStar(S.save, 0, 2),
			new XmlGenLiteral(")"), 
		]);

		// [57]	EnumeratedType ::= NotationType | Enumeration
		EnumeratedType = new XmlGenOr([
			NotationType.save,
			Enumeration.save,
		]);

		// [54]	AttType ::=	StringType | TokenizedType | EnumeratedType
		AttType = new XmlGenOr([
			TokenizedType.save,
			EnumeratedType.save,
			StringType.save
		]);

		// [60]	DefaultDecl ::=	'#REQUIRED' | '#IMPLIED' | (('#FIXED' S)? AttValue)	
		DefaultDecl = new XmlGenOr([
			new XmlGenLiteral("#REQUIRED"), 
			new XmlGenLiteral("#IMPLIED"), 
			new XmlGenSeq([
				new XmlGenStar(
					new XmlGenSeq([
						new XmlGenLiteral("#FIXED"), 
						S.save
					]), 0, 2
				),
				AttValue.save
			])
		]);

		// [53]	AttDef ::= S Name S AttType S DefaultDecl
		AttDef = new XmlGenSeq([
			S.save, Name.save, S.save, AttType.save, S.save, DefaultDecl.save
		]);

		// [52]	AttlistDecl ::= '<!ATTLIST' S Name AttDef* S? '>'
		AttlistDecl = new XmlGenSeq([
			new XmlGenLiteral("<!ATTLIST"), S.save, Name.save,
			new XmlGenStar(AttDef.save, 0, 3), new XmlGenStar(S.save, 0, 2), 
		]);

		/* [75] ExternalID ::= 'SYSTEM' S SystemLiteral 
							| 'PUBLIC' S PubidLiteral S SystemLiteral
		*/
		ExternalID = new XmlGenOr([
			new XmlGenSeq([ new XmlGenLiteral("SYSTEM"), S.save,
				SystemLiteral.save 
			]),
			new XmlGenSeq([ new XmlGenLiteral("PUBLIC"), S.save,
				PubidLiteral.save, S.save, SystemLiteral.save
			])
		]);

		// [81] EncName ::= [A-Za-z] ([A-Za-z0-9._] | '-')*
		EncName = new XmlGenSeq([
			new XmlGenOr([
				new XmlGenCharRange('A','Z'), new XmlGenCharRange('a','z')
			]),
			new XmlGenStar(
				new XmlGenOr([
					new XmlGenCharRange('A','Z'),
					new XmlGenCharRange('a','z'),
					new XmlGenCharRange('0','9'),
					new XmlGenLiteral("."),
					new XmlGenLiteral("_"),
					new XmlGenLiteral("-"),
				]), 0, 3
			)
		]);

		/* [80] EncodingDecl ::= S 'encoding' Eq 
					('"' EncName '"' | "'" EncName "'" )
		*/
		EncodingDecl = new XmlGenSeq([ S.save, new XmlGenLiteral("encoding"),
			Eq.save, 
			new XmlGenOr([
				new XmlGenSeq([
					new XmlGenLiteral("\""),
					EncName.save,
					new XmlGenLiteral("\""),
				]),
				new XmlGenSeq([
					new XmlGenLiteral("\""),
					EncName.save,
					new XmlGenLiteral("\""),
				])
			])
		]);

		/* [75] ExternalID ::= 'SYSTEM' S SystemLiteral 
						| 'PUBLIC' S PubidLiteral S SystemLiteral
		*/
		ExternalID = new XmlGenOr([
			new XmlGenSeq([new XmlGenLiteral("SYSTEM"), S.save,
				SystemLiteral.save
			]),
			new XmlGenSeq([new XmlGenLiteral("PUBLIC"), S.save,
				PubidLiteral.save, S.save, SystemLiteral.save
			]),
		]);

		// [76] NDataDecl ::= S 'NDATA' S Name
		NDataDecl = new XmlGenSeq([ S.save, new XmlGenLiteral("NDATA"),
			S.save, Name.save
		]);

		// [73] EntityDef ::= EntityValue | (ExternalID NDataDecl?)
		EntityDef = new XmlGenOr([
			EntityValue,
			new XmlGenSeq([ExternalID.save, 
				new XmlGenStar(NDataDecl.save, 0, 2)
			])
		]);

		// [74] PEDef ::= EntityValue | ExternalID
		PEDef = new XmlGenOr([EntityValue.save, ExternalID.save]);

		// [71] GEDecl ::= '<!ENTITY' S Name S EntityDef S? '>'
		GEDecl = new XmlGenSeq([
			new XmlGenLiteral("<!ENTITY"), S.save, Name.save, S.save,
			EntityDef.save, new XmlGenStar(S.save, 0, 2), new XmlGenLiteral(">")
		]);

		// [72] PEDecl ::= '<!ENTITY' S '%' S Name S PEDef S? '>'
		PEDecl = new XmlGenSeq([
			new XmlGenLiteral("<!ENTITY"), S.save, new XmlGenLiteral("%"), 
			S.save, Name.save, S.save, PEDef.save, new XmlGenStar(S.save, 0, 2),
		   	new XmlGenLiteral(">")
		]);

		// [65] Ignore ::= Char* - (Char* ('<![' | ']]>') Char*)
		Ignore = new XmlGenChar("<![]>"); // TODO Test

		/* [64] ignoreSectContents ::= Ignore ('<![' ignoreSectContents ']]>' 
			Ignore)*
		*/
		ignoreSectContents = new XmlGenSeq([Ignore.save,
			new XmlGenStar(
				new XmlGenSeq([
					new XmlGenLiteral("<!["),
					new XmlGenLiteral("]]>")
				])
			, 0, 3)
		]);

		// [63]	ignoreSect ::= '<![' S? 'IGNORE' S? '[' ignoreSectContents* ']]>'
		ignoreSect = new XmlGenSeq([
			new XmlGenLiteral("<!["),
			new XmlGenStar(S.save, 0, 2),
			new XmlGenLiteral("IGNORE"),
			new XmlGenStar(S.save, 0, 2),
			new XmlGenLiteral("["),
			new XmlGenStar(ignoreSectContents.save, 0, 3),
			new XmlGenLiteral("]]>")
		]);

		// [61] conditionalSect ::= includeSect | ignoreSect
		conditionalSect = new XmlGenOr([/*includeSect CYCLE ,*/ ignoreSect]);

		// [31] extSubsetDecl ::= ( markupdecl | conditionalSect | DeclSep)*
		extSubsetDecl = new XmlGenStar(
			new XmlGenOr([
				// makeupdecl.save TODO
				conditionalSect.save
				// DeclSep.save TODO
			]), 0, 3
		);

		/* [62] includeSect ::= '<![' S? 'INCLUDE' S? '[' extSubsetDecl ']]>'
		includeSect = new XmlGenSeq([
			new XmlGenLiteral("<!["),
			new XmlGenStar(S.save, 0, 2),
			new XmlGenLiteral("INCLUDE"),
			new XmlGenStar(S.save, 0, 2),
			new XmlGenLiteral("["),
			extSubsetDecl.save,
			new XmlGenLiteral("]]>")
		]);*/

		// [70] EntityDecl ::= GEDecl | PEDecl
		EntityDecl = new XmlGenOr([GEDecl.save, PEDecl.save]);

		// [77] TextDecl ::= '<?xml' VersionInfo? EncodingDecl S? '?>'
		TextDecl = new XmlGenSeq([
			new XmlGenLiteral("<?xml"), 
			new XmlGenStar(VersionInfo.save, 0, 2), EncodingDecl.save,
			S.save, new XmlGenLiteral("?>")
		]);

		// [83] PublicID ::= 'PUBLIC' S PubidLiteral
		PublicID = new XmlGenSeq([
			new XmlGenLiteral("PUBLIC"), S.save, PubidLiteral.save
		]);	

		/* [82] NotationDecl ::= '<!NOTATION' S Name S 
		 		  (ExternalID | PublicID) S? '>'
		*/
		NotationDecl = new XmlGenSeq([
			new XmlGenLiteral("<!NOTATION"), S.save, Name.save, S.save,
			new XmlGenOr([ExternalID.save, PublicID.save]), 
			new XmlGenStar(S.save, 0, 2), new XmlGenLiteral(">")
		]);
	}

	XmlGen S; // 3
	XmlGen NameStartChar; // 4
	XmlGen NameChar; // 4a
	XmlGen Name; // 5
	XmlGen Nmtoken; // 7
	XmlGen EntityValue; // 9
	XmlGen AttValue; // 10
	XmlGen SystemLiteral; // 11
	XmlGen PubidLiteral; // 12
	XmlGen PubidChar; // 13
	XmlGen VersionInfo; // 24
	XmlGen Eq; // 25
	XmlGen VersionNum; // 26
	XmlGen extSubsetDecl; // 33
	XmlGen Mixed; // 52
	XmlGen AttlistDecl; // 52
	XmlGen AttDef; // 53
	XmlGen AttType; // 54
	XmlGen StringType; // 55
	XmlGen TokenizedType; // 56
	XmlGen EnumeratedType; // 57
	XmlGen NotationType; // 58
	XmlGen Enumeration; // 59
	XmlGen DefaultDecl; // 60
	XmlGen conditionalSect; // 61
	XmlGen includeSect; // 62
	XmlGen ignoreSect; // 63
	XmlGen ignoreSectContents; // 64
	XmlGen Ignore; // 65
	XmlGen CharRef; // 66
	XmlGen Reference; // 67
	XmlGen EntityRef; // 68
	XmlGen PEReference; // 69
	XmlGen EntityDecl; // 70
	XmlGen GEDecl; // 71
	XmlGen PEDecl; // 72
	XmlGen EntityDef; // 73
	XmlGen PEDef; // 74
	XmlGen ExternalID; // 75
	XmlGen NDataDecl; // 76
	XmlGen TextDecl; // 77
	XmlGen EncodingDecl; // 80
	XmlGen EncName; // 81
	XmlGen NotationDecl; // 82
	XmlGen PublicID; // 83
}

unittest {
	auto x = new XmlGenGenerator();
	auto g = x.Mixed;
	while(!g.empty) {
		log(g.front);
		g.popFront();
	}
}

module std.xml2.testgrammar;

import std.xml2.testing : XmlGen, XmlGenSeq, XmlGenOr, XmlGenString,
	   XmlGenLiteral, XmlGenStar, XmlGenChar, XmlGenCharRange;

import std.experimental.logger;

/* The '+' grammar symbol will be translated as 1,2.
The '*' grammar symbol will be translated as 0,1,2.
*/

class XmlGenGenerator {
	this() {
		// [ 3] S ::= (#x20 | #x9 | #xD | #xA)+
		S = new XmlGenStar(
			new XmlGenOr([
				new XmlGenLiteral(" "),	
				new XmlGenLiteral("\n"),	
				new XmlGenLiteral("\t")
			]), 1, 3
		);

		// [ 4] NameStartChar ::= ":" | [A-Z] | "_" | [a-z] | [#xC0-#xD6]
		NameStartChar = new XmlGenOr([ new XmlGenLiteral(":"), 
			new XmlGenLiteral(":"), new XmlGenCharRange('A', 'Z'),
			new XmlGenCharRange('A', 'Z'), new XmlGenCharRange('\xC0', '\xD6')
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
		
		// [13] PubidChar ::= #x20 | #xD | #xA | [a-zA-Z0-9] | [-'()+,./:=?;!*#@$_%]
		PubidChar = new XmlGenChar();
		
		// [12] PubidLiteral ::= '"' PubidChar* '"' | "'" (PubidChar - "'")* "'"
		PubidLiteral = new XmlGenOr([
			new XmlGenSeq([
				new XmlGenLiteral("\""),
				new XmlGenStar(PubidChar.save, 0, 3),
				new XmlGenLiteral("\"")
			]),
			new XmlGenSeq([
				new XmlGenLiteral("'"),
				new XmlGenStar(new XmlGenChar("'"), 0, 3),
				new XmlGenLiteral("'")
			])
		]);

		// [25] Eq ::= S? '=' S?
		Eq = new XmlGenSeq([ S.save, new XmlGenLiteral("="), S.save ]);

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

		// [69] PEReference ::= '%' Name ';'
		PEReference = new XmlGenSeq([
			new XmlGenLiteral("%"),
			Name.save,
			new XmlGenLiteral(";"),
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

		// [77] TextDecl ::= '<?xml' VersionInfo? EncodingDecl S? '?>'
		TextDecl = new XmlGenSeq([
			new XmlGenLiteral("<?xml"), VersionInfo.save, EncodingDecl.save,
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
			S.save, new XmlGenLiteral(">")
		]);
	}

	XmlGen S; // 3
	XmlGen NameStartChar; // 4
	XmlGen NameChar; // 4a
	XmlGen Name; // 5
	XmlGen SystemLiteral; // 11
	XmlGen PubidLiteral; // 12
	XmlGen PubidChar; // 13
	XmlGen Eq; // 25
	XmlGen VersionInfo; // 24
	XmlGen VersionNum; // 26
	XmlGen CharRef; // 66
	XmlGen EntityRef; // 68
	XmlGen PEReference; // 69
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
	while(!x.TextDecl.empty) {
		//log(x.TextDecl.front);
		x.TextDecl.popFront();
	}
}

module std.xml2.lexer;

import core.exception;

import std.xml2.testing;
import std.xml2.misc;
import std.xml2.exceptions;

import std.exception;
import std.array;
import std.conv;
import std.format;
import std.meta;
import std.typecons;
import std.range.primitives;
import std.traits;
import std.stdio;

version(unittest) {
	import std.experimental.logger;
}

alias Attributes(Input) = Input[Input];

alias TrackPosition = Flag!"TrackPosition";
alias KeepComments = Flag!"KeepComments";
alias EagerAttributeParse = Flag!"EagerAttributeParse";

enum ErrorHandling {
	exceptions,
	asserts,
	ignore
}

enum NodeType {
	Unknown,
	StartTag,
	EndTag,
	Entity,
	EmptyTag,
	CData,
	Text,
	AttributeList,
	ProcessingInstruction,
	DocType,
	Element,
	Comment,
	Notation,
	Prolog,
}

void toString(NodeType type, void delegate(const(char)[]) @trusted output) @safe {
	final switch(type) {
		case NodeType.Unknown: output("Unknown"); break;
		case NodeType.StartTag: output("StartTag"); break;
		case NodeType.EndTag: output("EndTag"); break;
		case NodeType.EmptyTag: output("EmptyTag"); break;
		case NodeType.Entity: output("Entity"); break;
		case NodeType.CData: output("CData"); break;
		case NodeType.Text: output("Text"); break;
		case NodeType.AttributeList: output("AttributeList"); break;
		case NodeType.ProcessingInstruction: output("ProcessingInstruction"); break;
		case NodeType.DocType: output("DocType"); break;
		case NodeType.Element: output("Element"); break;
		case NodeType.Comment: output("Comment"); break;
		case NodeType.Notation: output("Notation"); break;
		case NodeType.Prolog: output("Prolog"); break;
	}
}

void reproduceNodeTypeString(T,O)(NodeType type, ref O output) @safe {
	void toT(string s, ref O output) @trusted {
		foreach(it; s) {
			output.put(to!T(it));
		}
	}

	final switch(type) {
		case NodeType.Unknown: toT("Unknown", output); break;
		case NodeType.StartTag: toT("<", output); break;
		case NodeType.EndTag: toT(">", output); break;
		case NodeType.EmptyTag: toT("</", output); break;
		case NodeType.CData: toT("<![CDATA[", output); break;
		case NodeType.Entity: toT("<!ENTITY", output); break;
		case NodeType.Text: toT("Text", output); break;
		case NodeType.AttributeList: toT("<!ATTLIST", output); break;
		case NodeType.ProcessingInstruction: toT("<?", output); break;
		case NodeType.DocType: toT("<!DOCTYPE", output); break;
		case NodeType.Element: toT("Element", output); break;
		case NodeType.Comment: toT("<!--", output); break;
		case NodeType.Notation: toT("<!NOTATION", output); break;
		case NodeType.Prolog: toT("<?xml", output); break;
	}
}

@safe unittest {
	foreach(T; AliasSeq!(string,wstring,dstring)) {
		foreach(it; __traits(allMembers, NodeType)) {
			NodeType node = __traits(getMember, NodeType, it);
			auto app = appender!T();
			static assert(isOutputRange!(typeof(app),T));
			reproduceNodeTypeString!T(node, app);

			if(node == NodeType.Unknown) {
				assert(app.data == "Unknown");
			} else if(node == NodeType.Text) {
				assert(app.data == "Text");
			} else if(node == NodeType.Element) {
				assert(app.data == "Element");
			} else if(node == NodeType.EndTag) {
				assert(app.data[0] == '>');
			} else {
				assert(app.data[0] == '<');
			}
		}
	}
}
void checkCondition(R = XMLException, 
		ErrorHandling errorHandling = ErrorHandling.exceptions, 
		E)
		(E expression, string msg, 
		string file = __FILE__, size_t line = __LINE__,
   		string func = __FUNCTION__)
{
	import std.format : format;

	if(!expression) {
		auto s = format("%s %s", func, msg);
		static if(errorHandling == ErrorHandling.asserts) {
			throw new AssertError(s, file, line);
		} else static if(errorHandling == ErrorHandling.exceptions) {
			throw new R(s, file, line);
		}
	}
}

struct Node(T) {
	T input;
	NodeType nodeType;

	void toString(void delegate(const(char)[]) @trusted sink) @safe {
		import std.conv : to;
		sink("Node(");	
		this.nodeType.toString(sink);
		sink(",");
		sink(to!string(this.input));
		sink(")");
	}
}

struct Slicer(T) {
	T input;
	size_t curPos;
	Node!T node;
	bool buildNext;

	this(T input) {
		this.input = input;
		this.curPos = 0;
		this.buildNext = true;
		this.eatWhitespace();
	}

	private void eatWhitespace() {
		for(; this.curPos < this.input.length; ++this.curPos) {
			static if(ElementEncodingType!(T).sizeof == 1
					|| ElementEncodingType!(T).sizeof == 2
					|| ElementEncodingType!(T).sizeof == 4) 
			{
				if(this.input[this.curPos] != 0x20
					&& this.input[this.curPos] != 0x09
					&& this.input[this.curPos] != 0x0d
					&& this.input[this.curPos] != 0x0A)
				{
					break;
				}
			}
		}
	}

	NodeType getAndEatNodeType() {
		checkCondition(this.curPos < this.input.length, "this.input must not be empty");
		if(this.input[this.curPos] == '<') {
			++curPos;

			checkCondition(this.curPos < this.input.length, "this.input must not be empty");
			if(this.input[this.curPos] == '!') {
				++curPos;

				if(testAndEatPrefix!("ELEMENT")()) {
					return NodeType.Element;
				} else if(testAndEatPrefix!("DOCTYPE")()) {
					return NodeType.DocType;
				} else if(testAndEatPrefix!("[CDATA[")()) {
					return NodeType.CData;
				} else if(testAndEatPrefix!("--")()) {
					return NodeType.Comment;
				} else if(testAndEatPrefix!("ATTLIST")()) {
					return NodeType.AttributeList;
				} else if(testAndEatPrefix!("NOTATION")()) {
					return NodeType.Notation;
				} else if(testAndEatPrefix!("ENTITY")()) {
					return NodeType.Entity;
				}
			} else if(this.input[this.curPos] == '?') {
				++this.curPos;
				return NodeType.ProcessingInstruction;
			} else if(this.input[this.curPos] == '/') {
				++this.curPos;
				return NodeType.EndTag;
			} else {
				return NodeType.StartTag;
			}
		} else if(this.input[this.curPos] != '>') {
			return NodeType.Text;
		}

		return NodeType.Unknown;
	}

	bool testAndEatPrefix(string prefix)() {
		for(size_t i = 0; i < prefix.length; ++i) {
			size_t idx = this.curPos + i;
			if(idx >= this.input.length 
					|| this.input[this.curPos + i] != prefix[i]) 
			{
				return false;
			}
		}

		this.curPos += prefix.length;
		return true;
	}

	bool testAndEatPrefix(char c)() {
		if(this.curPos < this.input.length && this.input[this.curPos] == c) {
			++this.curPos;
			return true;
		} else {
			return false;
		}
	}

	T eatUntil(S)(const S until) {
		import std.xml2.misc: indexOfX;

		auto idx = indexOfX(this.input[this.curPos .. $], until);
		T ret;
		if(idx == -1) {
			ret = this.input[this.curPos .. $];
		} else {
			ret = this.input[this.curPos .. this.curPos + idx];
		}
		this.curPos += idx;
		return ret;
	}

	T parseEntity() {
		import std.xml2.misc: indexOfX;

		auto idx = indexOfX(this.input, '\'', this.curPos);
		if(idx == -1) {
			idx = 0;
		} else {
			idx = indexOfX(this.input, '\'', this.curPos + idx + 1);
		}
		idx = indexOfX(this.input, '>', idx + 1);
		enforce!XMLException(idx != -1, "Failed to find '>'");

		auto ret = this.input[this.curPos .. idx];
		this.curPos = idx;
		
		return ret;
	}

	static bool compare(string c,S)(S s) {
		if(c.length != s.length) {
			return false;
		} else {
			enum cS = to!S(c);
			for(size_t i = 0; i < cS.length; ++i) {
				if(cS[i] != s[i]) {
					return false;
				}
			}

			return true;
		}
	}

	T balancedEatBraces() {
		size_t idx = this.curPos;
		int cnt = 1;
		int state = 0;
		while(idx < this.input.length) {
			if(this.input.length - idx > 3) {
				import std.stdio : writeln;
				/*writeln(this.input[idx .. idx+4], "%%", state, "%%",
					this.input[idx .. idx+3] == "-->", "%%", cnt, "%%",
					idx);*/
			}
			if(state == 0 && this.input[idx] == '>') {
				--cnt;
				if(cnt == 0) {
					break;
				}
			} else if(state == 0 && this.input.length - idx > 3 && 
					compare!("<!--")(this.input[idx .. idx+4]))
			{
				state = 3;
				idx += 3;
			} else if(state == 3 && this.input.length - idx > 2 && 
					compare!("-->")(this.input[idx .. idx+3]))
			{
				state = 0;
				idx += 2;
			} else if(state == 0 && this.input[idx] == '<') {
				++cnt;
			} else if(state == 0 && this.input[idx] == '"') {
				state = 2;
			} else if(state == 2 && this.input[idx] == '"') {
				state = 0;
			} else if(state == 0 && this.input[idx] == '\'') {
				state = 1;
			} else if(state == 1 && this.input[idx] == '\'') {
				state = 0;
			}
			++idx;
		}

		auto ret = this.input[this.curPos .. idx];
		this.curPos = idx;

		return ret;
	}

	void popFront() {
		if(this.buildNext) {
			this.front();
		}
		this.buildNext = true;
	}

	@property bool empty() const {
		return this.curPos >= this.input.length;
	}

	@property Node!T front() {
		if(!this.buildNext) {
			return this.node;
		}
		node.nodeType = this.getAndEatNodeType();
		final switch(node.nodeType) {
			case NodeType.Unknown:
				version(unittest) {
					throw new XMLException(
						"TODO: Error Handling", __FILE__, __LINE__
					);
				} else {
					break;
				}
			case NodeType.StartTag: { 
				node.input = this.eatUntil('>');
				if(node.nodeType == NodeType.StartTag
						&& !node.input.empty && node.input[$ - 1] == '/') 
				{
					node.nodeType = NodeType.EmptyTag;
				}
				this.testAndEatPrefix!'>'();
				break;
			}
			case NodeType.Entity:
				node.input = this.parseEntity();
				//log(node.input);
				//log(this.input[this.curPos .. $]);
				enforce!XMLException(this.testAndEatPrefix!'>'(),
					"Expected '>'"
				);
				break;
			case NodeType.EndTag:
				goto case NodeType.StartTag;
			case NodeType.EmptyTag:
				assert(false, "can't be found here, is done one step later");
			case NodeType.CData: { 
				node.input = this.eatUntil("]]>");
				enforce!XMLException(this.testAndEatPrefix!("]]>")(),
					"Expected ']]>'"
				);
				break;
			}
			case NodeType.Text: { 
				node.input = this.eatUntil('<');
				break;
			}
			case NodeType.AttributeList:
				goto case NodeType.StartTag;
			case NodeType.ProcessingInstruction:
				goto case NodeType.Prolog;
			case NodeType.DocType: {
				node.input = this.balancedEatBraces();
				this.testAndEatPrefix!('>')();
				break;
			}
			case NodeType.Element:
				goto case NodeType.StartTag;
			case NodeType.Comment: { 
				node.input = this.eatUntil("-->");
				this.testAndEatPrefix!("-->")();
				break;
			}
			case NodeType.Notation:
				goto case NodeType.StartTag;
			case NodeType.Prolog: { 
				node.input = this.eatUntil("?>");
				if(node.input.indexOfX("xml ") == 0) {
					node.nodeType = NodeType.Prolog;
				}
				this.testAndEatPrefix!("?>")();
				break;
			}
		}

		this.eatWhitespace();
		this.buildNext = false;
		return node;
	}
}

struct Range(T) {
	auto eatUntil(T)(const T until) {
		auto app = appender!(ElementEncodingType!(Input)[])();
		while(!this.input.empty && !this.testAndEatPrefix(until, false)) {
			app.put(this.input.front);	
			this.popAndAdvance();
		}

		return app.data;
	}

	auto parseEntity() {
		auto app = appender!(ElementEncodingType!(Input)[])();
		while(!this.input.empty && this.input.front != '>' 
				&& this.input.front != '\'')
		{
			app.put(this.input.front);	
			this.popAndAdvance();
		}
		
		checkCondition(!this.input.empty, "this.input must not be empty");

		if(this.input.front == '>') {
			return app.data;
		} else {
			app.put(this.input.front);
			this.popAndAdvance();
			while(!this.input.empty && this.input.front != '\'') {
				app.put(this.input.front);	
				this.popAndAdvance();
			}

			checkCondition(!this.input.empty, "this.input must not be empty");
			app.put(this.input.front);
			this.popAndAdvance();

			while(!this.input.empty && this.input.front != '>') {
				app.put(this.input.front);	
				this.popAndAdvance();
			}

			return app.data;
		}
	}

	auto balancedEatBraces() {
		auto app = appender!(ElementEncodingType!(Input)[])();
		int cnt = 1;
		int state = 0;
		while(!this.input.empty) {
			//writeln(this.input.getBuffer(), " || ", state, '\n');
			if(state == 0 && this.input.front == '>') {
				--cnt;
				if(cnt == 0) {
					break;
				}
			} else if(state == 0 && testAndEatPrefix("<!--", false)) {
				foreach(it; 0 .. 3) {
					checkCondition(!this.input.empty, 
						"this.input must not be empty");
					app.put(this.input.front);
					this.input.popFront();
				}
				state = 3;
			} else if(state == 3 && testAndEatPrefix("-->", false)) {
				foreach(it; 0 .. 2) {
					checkCondition(!this.input.empty, 
						"this.input must not be empty");
					app.put(this.input.front);
					this.input.popFront();
				}
				state = 0;
			} else if(state == 0 && this.input.front == '"') {
				state = 2;
			} else if(state == 2 && this.input.front == '"') {
				state = 0;
			} else if(state == 0 && this.input.front == '<') {
				++cnt;
			} else if(state == 0 && this.input.front == '\'') {
				state = 1;
			} else if(state == 1 && this.input.front == '\'') {
				state = 0;
			}
			checkCondition(!this.input.empty, "this.input must not be empty");
			app.put(this.input.front);
			this.input.popFront();
		}
		return app.data;
	}

}


struct Lexer(Input, 
	Impl
) {

	Impl impl;

	this(Input input) {
		this.impl = Impl!Input(input);
	}

	@property bool empty() {
		return this.impl.empty;
	}

	@property Node!Input front() {
		return this.impl.front;
	}

	void popFront() {
		this.impl.popFront();
	}
}

unittest {
	import std.xml2.misc : toStringX;

	static struct Prefix {
		string prefix;
		NodeType type;
	}

	const auto prefixes = [
		Prefix("<xml>", NodeType.StartTag),
		Prefix("</xml>", NodeType.EndTag),
		Prefix("<xml/>", NodeType.EmptyTag),
 		// Just to check correct access, actually invalid node
		Prefix("</>", NodeType.EndTag),
		Prefix("<!ELEMENT>", NodeType.Element),
		Prefix("<!DOCTYPE>", NodeType.DocType),
		Prefix("<!NOTATION>", NodeType.Notation),
		Prefix("<![CDATA[]]>", NodeType.CData),
		Prefix("<!-- -->", NodeType.Comment),
		Prefix("<!ATTLIST>", NodeType.AttributeList),
		Prefix("<?Hello ?>", NodeType.ProcessingInstruction),
		Prefix("<?xml ?>", NodeType.Prolog),
		Prefix(">", NodeType.Unknown),
		Prefix("Test", NodeType.Text),
		Prefix("<!ELEMENT root EMPTY>", NodeType.Element),
		Prefix("<!ATTLIST root xml:lang CDATA #IMPLIED>",
				NodeType.AttributeList),
		Prefix("<!ENTITY utf16b SYSTEM \"../invalid/utf16b.xml\">",
				NodeType.Entity),
		Prefix("<!ELEMENT foo (root*)>", NodeType.Element),
		Prefix("<!ELEMENT root EMPTY>", NodeType.Element),
		Prefix("<!ENTITY % zz '&#60;!ENTITY tricky \"error-prone\" >' >",
			NodeType.Entity),
		Prefix("<!ENTITY % xx '&#37;zz;'>", NodeType.Entity)
	];

	foreach(T ; TestInputArray) {
		foreach(idx, it; prefixes) {
			import std.xml2.misc : indexOfX;
			//logf("'%s'", it.prefix);
			auto input = makeTestInputTypes!T(it.prefix);
			auto lexer = Lexer!(T,Slicer!T)(input);
			assert(!lexer.empty);

			if(it.type == NodeType.Unknown) {
				assertThrown!XMLException(lexer.front);
			} else {
				Node!T nt = lexer.front;
				assert(nt.nodeType == it.type, 
					format("idx %s, %s %s", idx, nt, it.type)
				);
				lexer.popFront();
				assert(lexer.empty);
			}
		}
	}
}


/*unittest { // eatuntil
	import std.algorithm.comparison : equal;
	import std.format : format;
	const auto strs = [
		"helo",
		">",
		"xml>",
		"<xml>"
	];

	foreach(T; TestInputTypes) {
		foreach(P; AliasSeq!(TrackPosition.yes, TrackPosition.no)) {
			foreach(it; strs) {
				for(size_t i = 0; i < it.length; ++i) {
					//logf("%u '%c' %s", i, it[i], T.stringof);
					auto input = makeTestInputTypes!T(it);
					auto lexer = Lexer!(T,P)(input);
					auto slice = lexer.eatUntil(it[i]);

					assert(equal(slice, it[0 .. i]), 
						format("%u '%c' '%s' '%s' %s", 
							i, it[i], slice, it[0 .. i], T.stringof
						)
					);

					if(i+1 == it.length) {
						assert(lexer.input.front == it[i],
							format("%s\n%s == %s,\ni %d\nT %s\nP %s",
								it, lexer.input.front, it[i], i, T.stringof,
							   	P.stringof
							)
						);
					}
				}
			}
		}
	}
}*/



unittest {
	foreach(T ; TestInputArray) {
		auto input = makeTestInputTypes!T("<xml></xml>");
		auto lexer = Lexer!(T,Slicer!T)(input);
		assert(!lexer.empty);
		lexer.popFront();
		assert(!lexer.empty);
		lexer.popFront();
		assert(lexer.empty);
	}
}

unittest { 
	const auto testStrs = [
		q{<!DOCTYPE foo [
		  <!ELEMENT foo (root*)>
		  <!ELEMENT root EMPTY>
		  <!ENTITY utf16b SYSTEM "../invalid/utf16b.xml">
		  <!ENTITY utf16l SYSTEM "../invalid/utf16l.xml"> ]>},
		q{<!DOCTYPE root [
		  <!ELEMENT root EMPTY>
		  <!ATTLIST root xml:lang CDATA #IMPLIED> ]>},
	];

	foreach(T ; TestInputArray) {
		foreach(testStrIt; testStrs) {
			auto input = makeTestInputTypes!T(testStrIt);
			auto lexer = Lexer!(T,Slicer!T)(input);
			auto node = lexer.front;
			lexer.popFront();
			assert(lexer.empty);
		}
	}
}

unittest { // balancedEatUntil
	const auto testStrs = [
q{<!DOCTYPE doc
[
<!ELEMENT doc (#PCDATA)>
<!ENTITY % pe "<!---->">
%pe;<!---->%pe;
]>},
"<!DOCTYPE []>",
"<!DOCTYPE [ <!EL >]>",
"<!DOCTYPE [ <!EL > <!-- -->]>",
q{
<!DOCTYPE doc
[
<!ELEMENT doc ANY>} ~
"\n<!--NOTE: XML doesn't specify whether this is a choice or a seq-->\n" ~
q{<!ELEMENT a (doc?)>
<!ELEMENT b (doc|a)>
<!ELEMENT c (
doc
|
a
|
c?
)>
]>
},
q{<!DOCTYPE doc
[
<!ELEMENT doc EMPTY>
<!NOTATION not1 PUBLIC "a b
cZ">} ~
"<!NOTATION not2 PUBLIC '09-()+,./:=?;!*#@$_%'>" ~
q{<!NOTATION not3 PUBLIC "09-()+,.'/:=?;!*#@$_%">
]>},
q{<!DOCTYPE doc
[
]>},
q{<!DOCTYPE doc
[
<!ELEMENT doc EMPTY>
]>},
q{<!DOCTYPE doc
[
<!ELEMENT doc EMPTY>
<!NOTATION not1 PUBLIC "a b
cdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ">
]>},
q{<!DOCTYPE doc
[
<!ELEMENT doc EMPTY>
<!NOTATION not1 PUBLIC "a b
cdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ">} ~ 
"<!NOTATION not2 PUBLIC '0123456789-()+,./:=?;!*#@$_%'>" ~
"]>",
	];
	foreach(T ; TestInputArray) {
	//foreach(T ; AliasSeq!(CharInputRange!string)) {
		//pragma(msg, T);
		//foreach(P; AliasSeq!(TrackPosition.yes, TrackPosition.no)) {
			foreach(testStrIt; testStrs) {
				auto testStr = makeTestInputTypes!T(testStrIt);
				auto lexer = Lexer!(T,Slicer!T)(testStr);
				assert(!lexer.empty);
				auto node = lexer.front;
				lexer.popFront();
				assert(lexer.empty);


				/*assert(lexer.testAndEatPrefix('<'));
				assert(!lexer.input.empty);
				auto data = lexer.balancedEatBraces();
				assert(!lexer.input.empty, toStringX(data) ~ " " ~
					T.stringof);
				assert(lexer.testAndEatPrefix('>'));
				lexer.eatWhitespace();
				assert(lexer.empty, T.stringof ~ " \"" ~ 
					toStringX(lexer.input) ~ "\"");
				*/
			}
		//}
	}
}

unittest {
	import std.conv : to;

	const auto testStrs = [
		"<xml> Some text that should result in a textnode</xml>",
		"<xml foo=\"bar\"> Some text that should result in a textnode</xml>",
	];	

	foreach(T ; TestInputArray) {
		//pragma(msg, T);
		//foreach(P; AliasSeq!(TrackPosition.yes, TrackPosition.no)) {
			foreach(testStrIt; testStrs) {
				auto testStr = makeTestInputTypes!T(testStrIt);
				auto lexer = Lexer!(T,Slicer!T)(testStr);

				try {
					assert(!lexer.empty);
					auto start = lexer.front;
					lexer.popFront();
					assert(!lexer.empty);
					auto text = lexer.front;
					assert(text.nodeType == NodeType.Text);
					lexer.popFront();
					assert(!lexer.empty);
					auto end = lexer.front;
					lexer.popFront();
					assert(lexer.empty);
				} catch(Exception e) {
					logf("%s %s", e.toString(), T.stringof);
				}
			}
		//}
	}
}

unittest {
	import std.conv : to;

	const auto testStrs = [
		"<A/>"
	];	

	foreach(T ; TestInputArray) {
		//foreach(P; AliasSeq!(TrackPosition.yes, TrackPosition.no)) {
			foreach(testStrIt; testStrs) {
				auto testStr = makeTestInputTypes!T(testStrIt);
				auto lexer = Lexer!(T,Slicer!T)(testStr);
				assert(!lexer.empty);
				auto f = lexer.front;
			}
		//}
	}
}

unittest {
	import std.xml2.bom;
	auto s = readTextWithBOM("tests/xmltest/valid/sa/out/050.xml");
	//log(s);
	auto lexer = Lexer!(string,Slicer!string)(s);
	while(!lexer.empty) {
		auto f = lexer.front;
		//log(f);
		lexer.popFront();
		//log(lexer.input);
	}
	assert(lexer.empty);
}

unittest {
	import std.file : dirEntries, SpanMode, readText;
	import std.stdio : writeln;
	import std.path : extension;
	import std.string : indexOf;
	import std.algorithm.iteration : filter;
	int cnt = 0;
	int cntW = 0;
	foreach(string name; dirEntries("tests", SpanMode.depth)
			.filter!(a => extension(a) == ".xml"
				&& a.name.indexOf("not") == -1
				&& a.name.indexOf("invalid") == -1) /*
				&& a.name.indexOf("fail") == -1 
				&& a.name.indexOf("japa") == -1
				&& a.name.indexOf("valid/sa/out/049.xml") == -1
				&& a.name.indexOf("valid/sa/out/051.xml") == -1
				&& a.name.indexOf("valid/sa/out/089.xml") == -1
				&& a.name.indexOf("valid/sa/out/063.xml") == -1
				&& a.name.indexOf("valid/sa/out/062.xml") == -1
				&& a.name.indexOf("ibm05v03.xml") == -1
				&& a.name.indexOf("ibm05v04.xml") == -1
				&& a.name.indexOf("ibm05v02.xml") == -1
				&& a.name.indexOf("ibm07v01.xml") == -1
				&& a.name.indexOf("ibm02v01.xml") == -1
				&& a.name.indexOf("ibm87v01.xml") == -1
				&& a.name.indexOf("ibm85v01.xml") == -1
				&& a.name.indexOf("ibm89v01.xml") == -1
				&& a.name.indexOf("ibm86v01.xml") == -1
				&& a.name.indexOf("ibm88v01.xml") == -1
				&& a.name.indexOf("ibm66v01.xml") == -1
				&& a.name.indexOf("ibm04n20.xml") == -1
				&& a.name.indexOf("ibm04n17.xml") == -1
				&& a.name.indexOf("ibm04an04.xml") == -1
				&& a.name.indexOf("xml-1.1/018.xml") == -1
				&& a.name.indexOf("xml-1.1/016.xml") == -1
				&& a.name.indexOf("xml-1.1/020.xml") == -1
				&& a.name.indexOf("xml-1.1/032.xml") == -1
				&& a.name.indexOf("xml-1.1/056.xml") == -1
				&& a.name.indexOf("xml-1.1/033.xml") == -1
				&& a.name.indexOf("xml-1.1/021.xml") == -1
				&& a.name.indexOf("xml-1.1/019.xml") == -1
				&& a.name.indexOf("xml-1.1/017.xml") == -1
				&& a.name.indexOf("xml-1.1/out/018.xml") == -1
				&& a.name.indexOf("xml-1.1/out/015.xml") == -1
				&& a.name.indexOf("xml-1.1/out/017.xml") == -1
				&& a.name.indexOf("xml-1.1/out/021.xml") == -1
			)*/
		)
	{
		import std.utf : UTFException;
		import std.xml2.bom : readTextWithBOM;

		string s;
		try {
			++cnt;
			s = readTextWithBOM(name);
			++cntW;
		} catch(Exception e) {
			logf("%s %s", name, e.toString());
			continue;
		}

		log(name);

		outer: foreach(T ; TestInputArray) {
			//foreach(P; AliasSeq!(TrackPosition.yes, TrackPosition.no)) {
				//typeof(Lexer!(T,Slicer!T).front) f;
				try {
					auto testStr = makeTestInputTypes!T(s);
					auto lexer = Lexer!(T,Slicer!T)(testStr);
					while(!lexer.empty) {
						auto f = lexer.front;
						lexer.popFront();
					}
					assert(lexer.empty);
				} catch(UTFException e) {
					logf("%s %s %s", name, T.stringof, e.toString());
					break outer;
					//assert(false);
				} catch(Throwable e) {
					logf("%s %s %s", name, T.stringof, e.toString());
					break outer;
					//assert(false);
					//assert(false, e.toString());
				}
			//}
		}
	}

	logf("%s of %s could be read", cntW, cnt);
}


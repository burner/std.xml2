module std.xml2.lexer;

import std.xml2.testing;
import std.xml2.misc : toStringX;

import std.array : empty, back, appender, Appender;
import std.conv : to;
import std.typecons : Flag;
import std.range.primitives : ElementEncodingType, ElementType, hasSlicing,
	isInputRange;
import std.traits : isArray, isSomeString;

version(unittest) {
	import std.experimental.logger;
}

alias Attributes(Input) = Input[Input];

alias TrackPosition = Flag!"TrackPosition";
alias KeepComments = Flag!"KeepComments";
alias EagerAttributeParse = Flag!"EagerAttributeParse";

class XMLException : Exception {
	this(string msg, string file = __FILE__, int line = __LINE__) {
		super(msg, file, line);
	}

	this(XMLException old) {
		super(old.msg, old.file, old.line);
	}
}

struct SourcePosition(TrackPosition track) {
	static if(track) {
		size_t line = 1u;
		size_t column = 1u;
	}

	void advance(C)(C c) {
		static if(track) {
			if(c == '\n') {
				this.line = 1u;
				++this.column;
			} else {
				++this.line;
			}
		}
	}

	void toString(void delegate(const(char)[]) @trusted sink) const @safe {
		sink("Pos(");
		static if(track) {
			import std.conv : to;
			sink(to!string(this.line));
			sink(",");
			sink(to!string(this.column));
		}
		sink(")");
	}
}

unittest {
	SourcePosition!(TrackPosition.yes) sp;
	sp.advance('\n');
	SourcePosition!(TrackPosition.no) sp2;
	sp2.advance('\n');
}

enum NodeType {
	Unknown,
	StartTag,
	EndTag,
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

void reprodcueNodeTypeString(T,O)(NodeType type, ref O output) @safe {
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

struct Lexer(Input, 
	TrackPosition trackPosition = TrackPosition.yes,
	KeepComments keepComments = KeepComments.yes,
	EagerAttributeParse eagerAttributeParse = EagerAttributeParse.no
) {

	import std.xml2.misc : ForwardRangeInput;

	struct Node {
		NodeType nodeType;
		ElementEncodingType!(Input)[] input;
	
		SourcePosition!trackPosition position;
	
		Attributes!Input attributes;
	
		this(in NodeType nodeType) {
			this.nodeType = nodeType;
		}
	
		void toString(void delegate(const(char)[]) @trusted sink) @safe {
			import std.conv : to;
			sink("Node(");	
			this.nodeType.toString(sink);
			sink(",");
			this.position.toString(sink);
			sink(",");
			sink(to!string(this.input));
			sink(")");
		}
	}

	SourcePosition!trackPosition position;
	static if(isSomeString!Input || isArray!Input) {
		Input input;
	} else {
		ForwardRangeInput!(Input,16) input;
	}
	Node ret;
	bool buildNext;

	this(Input input) {
		static if(isSomeString!Input || isArray!Input) {
			this.input = input;
		} else {
			this.input = ForwardRangeInput!(Input,16)(input);
		}
		this.buildNext = true;
		this.eatWhitespace();
	}

	@property bool empty() {
		return this.input.empty;
	}

	void popFront() {
		this.buildNext = true;
	}

	private void popAndAdvance() {
		this.position.advance(this.input.front);
		this.input.popFront();
	}

	private void popAndAdvance(const size_t cnt) {
		for(size_t i = 0; i < cnt; ++i) {
			this.popAndAdvance();
		}	
	}

	import std.traits : isSomeChar;

	bool testAndEatPrefix(Prefix)(Prefix prefix, bool eatMatch = true) 
			if(isSomeChar!Prefix) 
	{
		assert(!this.input.empty);
		if(this.input.front == prefix) {
			if(eatMatch) {
				this.popAndAdvance();
			}
			return true;
		} else {
			return false;
		}
	}

	bool testAndEatPrefix(Prefix)(Prefix prefix, bool eatMatch = true) 
			if(!isSomeChar!Prefix) 
	{
		import std.xml2.misc : indexOfX;

		static if(isSomeString!(typeof(this.input)) ||
				isArray!(typeof(this.input))) 
		{
			auto idx = this.input.indexOfX(prefix);
		} else {
			this.input.prefetch();
			auto idx = this.input.getBuffer().indexOfX(prefix);
		}
		if(idx == 0) {
			if(eatMatch) {
				this.popAndAdvance(prefix.length);
			}
			return true;
		} else {
			return false;
		}
	}

	NodeType getAndEatNodeType() {
		assert(!this.input.empty);
		if(this.input.front == '<') {
			this.popAndAdvance();

			assert(!this.input.empty);
			if(this.input.front == '!') {
				this.popAndAdvance();
				if(testAndEatPrefix("ELEMENT")) {
					return NodeType.Element;
				} else if(testAndEatPrefix("DOCTYPE")) {
					return NodeType.DocType;
				} else if(testAndEatPrefix("[CDATA[")) {
					return NodeType.CData;
				} else if(testAndEatPrefix("--")) {
					return NodeType.Comment;
				} else if(testAndEatPrefix("ATTLIST")) {
					return NodeType.AttributeList;
				} else if(testAndEatPrefix("NOTATION")) {
					return NodeType.Notation;
				}
			} else if(this.input.front == '?') {
				this.popAndAdvance();
				return NodeType.ProcessingInstruction;
			} else if(this.input.front == '/') {
				this.popAndAdvance();
				return NodeType.EndTag;
			} else {
				return NodeType.StartTag;
			}
		} else if(this.input.front != '>') {
			return NodeType.Text;
		}

		return NodeType.Unknown;
	}

	static if(hasSlicing!Input || isSomeString!Input) {
		Input eatUntil(T)(const T until) {
			import std.xml2.misc: indexOfX;

			auto idx = indexOfX(this.input, until);
			if(idx == -1) {
				idx = this.input.length;
			}

			auto ret = this.input[0 .. idx];

			static if(TrackPosition.yes) {
				//this.popAndAdvance(idx > 0 ? idx - 1 : 0);
				this.popAndAdvance(idx);
			} else {
				this.input = this.input[idx .. $];
			}

			return ret;
		}
	} else {
		auto eatUntil(T)(const T until) {
			auto app = appender!(ElementEncodingType!(Input)[])();
			while(!this.input.empty && !this.testAndEatPrefix(until, false)) {
				app.put(this.input.front);	
				this.popAndAdvance();
			}

			return app.data;
		}
	}

	//ElementEncodingType!((Input)[]) balancedEatBraces() {
	auto balancedEatBraces() {
		//pragma(msg, ElementEncodingType!(Input)[].stringof);
		auto app = appender!(ElementEncodingType!(Input)[])();
		//pragma(msg, typeof(app).stringof);
		while(!this.input.empty 
				&& this.input.front != '[' || this.input.front != '>') 
		{
			app.put(this.input.front);	
			this.popAndAdvance();
		}

		if(this.input.front == '[') {
			this.testAndEatPrefix('[');
			while(!this.input.empty && this.input.front != '>') {
				Node tmp;
				ubyte[__traits(classInstanceSize, XMLException)] exception;
				bool didNotWork;
				this.frontImpl(&tmp, didNotWork, exception);

				//reprodcueNodeTypeString!(ElementType!Input)
				//	(tmp.nodeType, app);
			}
		}
		
		return app.data;
	}

	@property Node front() {
		if(this.buildNext) {
			if(this.input.empty) {
				throw new Exception("Input empty");
			} else {
				bool didNotWork = false;
				ubyte[__traits(classInstanceSize, XMLException)] exception;
				this.frontImpl(&this.ret, didNotWork, exception);
				this.buildNext = false;

				if(didNotWork) {
					throw new XMLException((cast(XMLException)exception.ptr));
				}
			}
		}
		return this.ret;
	}

	@property Node front(out bool didNotWork) {
		if(this.buildNext) {
			if(this.input.empty) {
				throw new Exception("Input empty");
			} else {
				ubyte[__traits(classInstanceSize, XMLException)] exception;
				this.frontImpl(&this.ret, didNotWork, exception);
				this.buildNext = false;
			}
		}
		return this.ret;
	}

	void frontImpl(Node* node, ref bool didNotWork, void[] exception) {
		//this.eatWhitespace();

		auto pos = this.position;
		const NodeType nodeType = this.getAndEatNodeType();

		import std.conv : emplace;
		import std.xml2.misc : indexOfX;

		emplace(node, nodeType);
		node.position = pos;

		final switch(nodeType) {
			case NodeType.Unknown:
				version(unittest) {
					emplace!XMLException(
						exception, "TODO: Error Handling", __FILE__, __LINE__);
					didNotWork = true;
				}
				break;
			case NodeType.StartTag: { 
				node.input = this.eatUntil('>');
				if(node.nodeType == NodeType.StartTag
						&& !node.input.empty && node.input.back == '/') 
				{
					node.nodeType = NodeType.EmptyTag;
				}
				this.testAndEatPrefix('>');
				break;
			}
			case NodeType.EndTag:
				goto case NodeType.StartTag;
			case NodeType.EmptyTag:
				assert(false, "can't be found here, is done one step later");
			case NodeType.CData: { 
				node.input = this.eatUntil("]]>");
				this.testAndEatPrefix("]]>");
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
				//goto case NodeType.StartTag;
				ElementEncodingType!(Input)[] tmp = this.balancedEatBraces();
				pragma(msg, typeof(tmp).stringof);
				//node.input = tmp;
				this.testAndEatPrefix('>');
				break;
			}
			case NodeType.Element:
				goto case NodeType.StartTag;
			case NodeType.Comment: { 
				node.input = this.eatUntil("-->");
				this.testAndEatPrefix("-->");
				break;
			}
			case NodeType.Notation:
				goto case NodeType.StartTag;
			case NodeType.Prolog: { 
				node.input = this.eatUntil("?>");
				if(node.input.indexOfX("xml ") == 0) {
					node.nodeType = NodeType.Prolog;
				}
				this.testAndEatPrefix("?>");
				break;
			}
		}

		this.eatWhitespace();
	}

	private void eatWhitespace() {
		import std.uni : isWhite;
		while(!this.input.empty && isWhite(this.input.front)) {
			this.popAndAdvance();
		}
	}
}

unittest { // eatuntil
	import std.algorithm.comparison : equal;
	import std.format : format;
	const auto strs = [
		"helo",
		">",
		"xml>",
		"<xml>"
	];

	foreach(T; TestInputTypes) {
		foreach(P; TypeTuple!(TrackPosition.yes, TrackPosition.no)) {
			foreach(it; strs) {
				for(size_t i = 0; i < it.length; ++i) {
					//logf("%u '%c' %s", i, it[i], T.stringof);
					auto input = makeTestInputTypes!T(it);
					auto lexer = Lexer!(T,P)(input);
					auto slice = lexer.eatUntil(it[i]);

					assert(equal(slice, it[0 .. i]), 
						format("%u '%c' '%s' '%s' %s", i, it[i], slice, it[0 .. i],
							T.stringof
						)
					);

					if(i+1 == it.length) {
						assert(lexer.input.front == it[i],
							format("%u '%c' '%s' '%s' %s '%s' T=%s P=%s", i, 
								it[i], slice, it[0 .. i], T.stringof,
								lexer.input, T.stringof, P.stringof
							)
						);
					}
				}
			}
		}
	}
}

unittest { // testAndEatPrefix
	foreach(T ; TestInputTypes) {
		auto input = makeTestInputTypes!T("<xml></xml>");
		auto lexer = Lexer!T(input);
		auto lexer2 = Lexer!T(input);
		assert(lexer.testAndEatPrefix("<xml"), T.stringof ~ " (" ~ 
			to!string(lexer.input) ~ ")");
		assert(lexer2.testAndEatPrefix('<'));
		assert(!lexer2.testAndEatPrefix('>'));
		assert(!lexer.testAndEatPrefix("</xml"));
	}
}

unittest { // eatWhitespace
	foreach(T ; TestInputTypes) {
		foreach(P; TypeTuple!(TrackPosition.yes, TrackPosition.no)) {
			auto input = makeTestInputTypes!T(" \t\n\r");
			auto lexer = Lexer!(T,P)(input);
			lexer.eatWhitespace();
			assert(lexer.empty);
		}
	}
}

unittest { // balancedEatUntil
	const auto testStrs = [
		"< < >>"
	];	

	foreach(T ; TestInputTypes) {
		foreach(P; TypeTuple!(TrackPosition.yes, TrackPosition.no)) {
			foreach(testStrIt; testStrs) {
				auto input = makeTestInputTypes!T(testStrIt);
				auto lexer = Lexer!(T,P)(input);

				assert(lexer.testAndEatPrefix('<'));
				auto data = lexer.balancedEatBraces();
				assert(lexer.testAndEatPrefix('>'));
			}
		}
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
		Prefix("Test", NodeType.Text)
	];

	foreach(T ; TestInputTypes) {
		foreach(P; TypeTuple!(TrackPosition.yes, TrackPosition.no)) {
			foreach(it; prefixes) {
				import std.xml2.misc : indexOfX;
				//logf("'%s'", it.prefix);
				auto input = makeTestInputTypes!T(it.prefix);
				auto lexer = Lexer!(T,P)(input);

				typeof(lexer.front) n;
				try {
					n = lexer.front;
				} catch(Exception e) {
				}
				assert(n.nodeType == it.type, it.prefix ~ "|" ~
					toStringX(lexer.input) ~ "|" ~ to!string(n.nodeType) ~ 
					" " ~ to!string(it.type) ~ " '" ~ toStringX(n.input) ~ 
					"' " ~ T.stringof);
			}
		}
	}
}

unittest {
	import std.conv : to;

	const auto testStrs = [
		"<xml> Some text that should result in a textnode</xml>",
		"<xml foo=\"bar\"> Some text that should result in a textnode</xml>",
	];	

	foreach(T ; TestInputTypes) {
		//pragma(msg, T);
		foreach(P; TypeTuple!(TrackPosition.yes, TrackPosition.no)) {
			foreach(testStrIt; testStrs) {
				auto testStr = makeTestInputTypes!T(testStrIt);
				auto lexer = Lexer!(T,P)(testStr);

				try {
					assert(!lexer.empty);
					auto start = lexer.front;
					lexer.popFront();
					assert(!lexer.empty);
					auto text = lexer.front;
					lexer.popFront();
					assert(!lexer.empty);
					auto end = lexer.front;
					lexer.popFront();
					assert(lexer.empty, to!string(lexer.input));
				} catch(Exception e) {
					logf("%s %s", e.toString(), T.stringof);
				}
			}
		}
	}
}

unittest {
	import std.conv : to;

	const auto testStrs = [
		"<A/>"
	];	

	foreach(T ; TestInputTypes) {
		foreach(P; TypeTuple!(TrackPosition.yes, TrackPosition.no)) {
			foreach(testStrIt; testStrs) {
				auto testStr = makeTestInputTypes!T(testStrIt);
				auto lexer = Lexer!(T,P)(testStr);
				assert(!lexer.empty);
				auto f = lexer.front;
			}
		}
	}
}

unittest {
	import std.file : dirEntries, SpanMode, readText;
	import std.stdio : writeln;
	import std.path : extension;
	import std.string : indexOf;
	import std.algorithm.iteration : filter;
	foreach(string name; dirEntries("tests", SpanMode.depth)
			.filter!(a => extension(a) == ".xml" 
				&& a.indexOf("not") == -1
				&& a.indexOf("invalid") == -1
				&& a.indexOf("fail") == -1
			)
		)
	{
		import std.utf : UTFException;
		log(name);

		try {
			auto s = readText(name);
			auto lexer = Lexer!(string,TrackPosition.yes)(s);
			while(!lexer.empty) {
				auto f = lexer.front;
				//log(f);
				lexer.popFront();
			}
		} catch(UTFException e) {
		} catch(Exception e) {
			//log(name, e.toString());
		}
	}
}

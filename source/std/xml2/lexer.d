module std.xml2.lexer;

import std.xml2.testing;

import std.array : empty, back;
import std.typecons : Flag;
import std.range.primitives : ElementEncodingType, ElementType, hasSlicing;

version(unittest) {
	import std.experimental.logger;
}

alias Attributes(Input) = Input[Input];

alias TrackPosition = Flag!"TrackPosition";
alias KeepComments = Flag!"KeepComments";
alias EagerAttributeParse = Flag!"EagerAttributeParse";

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
		case NodeType.Unknown: output("Unknown");
		case NodeType.StartTag: output("StartTag");
		case NodeType.EndTag: output("EndTag");
		case NodeType.EmptyTag: output("EmptyTag");
		case NodeType.CData: output("CData");
		case NodeType.Text: output("Text");
		case NodeType.AttributeList: output("AttributeList");
		case NodeType.ProcessingInstruction: output("ProcessingInstruction");
		case NodeType.DocType: output("DocType");
		case NodeType.Element: output("Element");
		case NodeType.Comment: output("Comment");
		case NodeType.Notation: output("Notation");
		case NodeType.Prolog: output("Prolog");
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
	ForwardRangeInput!(Input,16) input;
	Node ret;
	bool buildNext;

	this(Input input) {
		this.input = ForwardRangeInput!(Input,16)(input);
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

	import std.traits : isSomeChar, isSomeString;

	bool testAndEatPrefix(Prefix)(Prefix prefix) if(isSomeChar!Prefix) {
		assert(!this.input.empty);
		if(this.input.front == prefix) {
			this.popAndAdvance();
			return true;
		} else {
			return false;
		}
	}

	bool testAndEatPrefix(Prefix)(Prefix prefix) if(!isSomeChar!Prefix) {
		import std.xml2.misc : indexOfX;
		import std.traits : isArray;

		static if(isArray!(typeof(this.input))) {
			auto idx = this.input.indexOfX(prefix);
		} else {
			//this.input.prefetch();
			//auto idx = this.input.indexOfX(this.input.getBuffer());
			auto idx = -1;
		}
		if(idx == 0) {
			this.popAndAdvance(prefix.length);
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
				this.popAndAdvance(idx);
			} else {
				this.input = this.input[idx .. $];
			}

			return ret;
		}
	} else {
		import std.array : appender, Appender;
		auto eatUntil(T)(const T until) {
			auto app = appender!(ElementType!(Input)[])();
			while(this.input.empty && !this.testAndEatPrefix(until)) {
				app.put(this.input.front);	
				this.popAndAdvance();
			}

			return app.data;
		}
	}

	@property Node front() {
		if(this.buildNext) {
			if(this.input.empty) {
				throw new Exception("Input empty");
			} else {
				this.frontImpl(&this.ret);
				this.buildNext = false;
			}
		}
		return this.ret;
	}

	void frontImpl(Node* node) {
		//this.eatWhitespace();

		auto pos = this.position;
		const NodeType nodeType = this.getAndEatNodeType();

		import std.conv : emplace;
		import std.xml2.misc : indexOfX;

		emplace(node, nodeType);
		node.position = pos;

		final switch(nodeType) {
			case NodeType.Unknown:
				version(unittest) log("TODO: Error Handling ", pos);
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
			case NodeType.DocType:
				goto case NodeType.StartTag;
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

unittest { // testAndEatPrefix
	foreach(T ; TestInputTypes) {
		auto input = makeTestInputTypes!T("<xml></xml>");
		auto lexer = Lexer!T(input);
		auto lexer2 = Lexer!T(input);
		assert(lexer.testAndEatPrefix("<xml"));
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

unittest {
	import std.conv : to;
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

				auto n = lexer.front;
				//log(T.stringof);
				assert(n.nodeType == it.type, it.prefix ~ "|" ~
					toStringX(lexer.input) ~ "|" ~ to!string(n.nodeType) ~ 
					" " ~ to!string(it.type) ~ " '" ~ toStringX(n.input) ~ 
					"' " ~ T.stringof ~ " " ~
					to!string(indexOfX(n.input, "xml ")));
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
			}
		}
	}
}

/*unittest {
	import std.conv : to;

	const auto testStrs = [
		"<̀A/>"
	];	

	foreach(T ; TestInputTypes) {
		//pragma(msg, T);
		foreach(P; TypeTuple!(TrackPosition.yes, TrackPosition.no)) {
			foreach(testStrIt; testStrs) {
				log(T.stringof);
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
			//warning(e.toString());
		}
	}
}*/

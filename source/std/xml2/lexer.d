module std.xml2.lexer;

import std.xml2.testing;

import std.array : empty;
import std.typecons : Flag;

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
	DocType,
	Element,
	Comment,
	Notation,
	Prolog,
}

struct Node(Input) {
	NodeType nodeType;
	Input input;

	Attributes!Input attributes;

	this(in NodeType nodeType) {
		this.nodeType = nodeType;
	}
}

struct Lexer(Input, 
	TrackPosition trackPosition = TrackPosition.yes,
	KeepComments keepComments = KeepComments.yes,
	EagerAttributeParse eagerAttributeParse = EagerAttributeParse.no
) {

	SourcePosition!trackPosition position;
	Input input;
	Node!Input ret;
	bool buildNext;

	this(Input input) {
		this.input = input;
		this.buildNext = true;
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
		if(this.input.front == prefix) {
			this.popAndAdvance();
			return true;
		} else {
			return false;
		}
	}

	bool testAndEatPrefix(Prefix)(Prefix prefix) if(!isSomeChar!Prefix) {
		while(!this.input.empty && !prefix.empty && 
				this.input.front == prefix.front) 
		{
			this.popAndAdvance();
			prefix.popFront();
		}
	
		if(prefix.empty) {
			return true;
		} else {
			return false;
		}
	}

	NodeType getAndEatNodeType() {
		if(this.input.front == '<') {
			this.popAndAdvance();

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
				if(testAndEatPrefix("xml")) {
					return NodeType.Prolog;
				}
			} else if(this.input.front == '/') {
				this.popAndAdvance();
				return NodeType.EmptyTag;
			} else {
				return NodeType.StartTag;
			}
		} else if(this.input.front != '>') {
			return NodeType.Text;
		}

		return NodeType.Unknown;
	}

	import std.range.primitives;

	static if(hasSlicing!Input || isSomeString!Input) {
		Input eatUntil(T)(const T until) {
			import std.string : indexOf;
			import std.xml2.misc: indexOf;
			static if(isSomeString!Input) { // TODO: Fix overload resulotion
				auto idx = this.input.indexOf(until);
			} else {
				auto idx = std.xml2.misc.indexOf(this.input,until);
			}
			//assert(idx != -1);
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

	@property Node!Input front() {
		if(this.buildNext) {
			this.frontImpl(&this.ret);
			this.buildNext = false;
		}
		return this.ret;
	}

	void frontImpl(Node!Input* node) {
		this.eatWhitespace();

		const NodeType nodeType = getAndEatNodeType();

		import std.conv : emplace;

		emplace(node, nodeType);

		final switch(nodeType) {
			case NodeType.Unknown:
				version(unittest) log("TODO: Error Handling");
			case NodeType.StartTag: { 
				node.input = this.eatUntil('>');
				this.testAndEatPrefix('>');
				break;
			}
			case NodeType.EndTag:
				goto case NodeType.StartTag;
			case NodeType.EmptyTag:
				goto case NodeType.StartTag;
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
				this.testAndEatPrefix("?>");
				break;
			}
		}
	}

	private void eatWhitespace() {
		import std.uni : isWhite;
		while(!this.input.empty && isWhite(this.input.front)) {
			this.popAndAdvance();
		}
	}
}

unittest {
	foreach(T ; TestInputTypes) {
		auto input = makeTestInputTypes!T("<xml></xml>");
		auto lexer = Lexer!T(input);
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

	static struct Prefix {
		string prefix;
		NodeType type;
	}

	const auto prefixes = [
		Prefix("<xml>", NodeType.StartTag),
		Prefix("</xml>", NodeType.EmptyTag),
		Prefix("<!ELEMENT>", NodeType.Element),
		Prefix("<!DOCTYPE>", NodeType.DocType),
		Prefix("<!NOTATION>", NodeType.Notation),
		Prefix("<![CDATA[]]>", NodeType.CData),
		Prefix("<!-- -->", NodeType.Comment),
		Prefix("<!ATTLIST>", NodeType.AttributeList),
		Prefix("<?xml?>", NodeType.Prolog),
		Prefix(">", NodeType.Unknown),
		Prefix("Test", NodeType.Text)
	];

	foreach(T ; TestInputTypes) {
		//pragma(msg, T);
		foreach(P; TypeTuple!(TrackPosition.yes, TrackPosition.no)) {
			foreach(it; prefixes) {
				//logf("%s", it.prefix);
				auto input = makeTestInputTypes!T(it.prefix);
				auto lexer = Lexer!(T,P)(input);

				auto n = lexer.front;
				assert(n.nodeType == it.type, 
					to!string(n.nodeType) ~ " " ~ to!string(it.type));
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

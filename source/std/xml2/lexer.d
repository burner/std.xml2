module std.xml2.lexer;

import std.xml2.testing;

import std.array : empty;
import std.typecons : Flag;

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

	this(Input input) {
		this.input = input;
	}

	@property bool empty() {
		return this.input.empty;
	}

	private void popAndAdvance() {
		this.position.advance(this.input.front);
		this.input.popFront();
	}

	bool testAndEatPrefix(Prefix)(Prefix prefix) {
		while(!this.input.empty && !prefix.empty && 
				this.input.front == prefix.front) 
		{
			popAndAdvance();
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

	@property Node!Input front() {
		Node!Input ret;
		this.frontImpl(&ret);
		return ret;
	}

	void frontImpl(Node!Input* node) {
		this.eatWhitespace();

		const NodeType type = getAndEatNodeType();

		import std.conv : emplace;

		emplace(node, type);
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

	const Prefix[11] prefixes = [
		Prefix("<xml", NodeType.StartTag),
		Prefix("</xml", NodeType.EmptyTag),
		Prefix("<!ELEMENT", NodeType.Element),
		Prefix("<!DOCTYPE", NodeType.DocType),
		Prefix("<!NOTATION", NodeType.Notation),
		Prefix("<![CDATA[", NodeType.CData),
		Prefix("<!--", NodeType.Comment),
		Prefix("<!ATTLIST", NodeType.AttributeList),
		Prefix("<?xml", NodeType.Prolog),
		Prefix(">", NodeType.Unknown),
		Prefix("Test", NodeType.Text)
	];

	foreach(T ; TestInputTypes) {
		foreach(P; TypeTuple!(TrackPosition.yes, TrackPosition.no)) {
			foreach(it; prefixes) {
				auto input = makeTestInputTypes!T(it.prefix);
				auto lexer = Lexer!(T,P)(input);

				auto n = lexer.front;
				assert(n.nodeType == it.type, to!string(n.nodeType));
			}
		}
	}
}

module std.xml2.testing;

import std.array : empty, front, popFront, appender, Appender;
import std.typecons : TypeTuple;
import std.range.primitives : ElementType, ElementEncodingType;
import std.random : Random, uniform;
import std.experimental.logger;

alias TestInputTypes = TypeTuple!(
	string, wstring, dstring,
	char[], wchar[], dchar[],
	immutable(ubyte)[], immutable(ushort)[], immutable(uint)[],
	CharInputRange!string, CharInputRange!wstring, CharInputRange!dstring
);

struct CharInputRange(T) {
	T input;

	this(string input) {
		import std.conv : to;
		this.input = to!T(input);
	}

	@property auto front() {
		return this.input.front;
	}

	@property bool empty() {
		return this.input.empty;
	}

	@property void popFront() {
		this.input.popFront();
	}
}

unittest {
	static assert(is(ElementType!(CharInputRange!string) == dchar));
	static assert(is(ElementEncodingType!(CharInputRange!string) == dchar));
}

T makeTestInputTypes(T,S)(S s) {
	import std.traits : isArray, isSomeString, isUnsigned;

	import std.conv : to;
	static if(isSomeString!T) {
		return to!T(s);
	} else static if(isArray!T && is(ElementType!T == immutable(ubyte))) {
		auto sCopy = to!string(s);
		return cast(immutable(ubyte)[])sCopy;
	} else static if(isArray!T && is(ElementType!T == immutable(ushort))) {
		auto sCopy = to!wstring(s);
		return cast(immutable(ushort)[])sCopy;
	} else static if(isArray!T && is(ElementType!T == immutable(uint))) {
		auto sCopy = to!dstring(s);
		return cast(immutable(uint)[])sCopy;
	} else {
		return T(s);
	}
}

alias XmlGenOut = Appender!string;
alias XmlGenRnd = Random;

abstract class XmlGen {
	bool gen(ref XmlGenOut, ref XmlGenRnd);
	void popFront() {}
}

class XmlGenSeq : XmlGen {
	this(XmlGen[] seq) {
		this.seq = seq;
	}

	override bool gen(ref XmlGenOut o, ref XmlGenRnd r) {
		bool ret = false;
		for(size_t i = 0; i < this.seq.length; ++i) {
			auto t = this.seq[i].gen(o, r);
			ret = ret || t;
		}

		return ret;
	}

	override void popFront() {

	}

	XmlGen[] seq;
}

unittest {
	auto g = new XmlGenSeq([
		new XmlGenLiteral("A"),
		new XmlGenLiteral("B"),
		new XmlGenStar(
			new XmlGenLiteral("C"),
			0,4
		)
	]);

	string[] rslt = [ "AB", "ABC", "ABCC", "ABCCC"];
	size_t rsltIdx = 0;

	auto app = appender!string();
	XmlGenRnd r;

	g.gen(app,r);
	do {
		assert(app.data == rslt[rsltIdx], app.data ~ " |" ~ rslt[rsltIdx]
			~ "|");
		++rsltIdx;
		app = appender!string();
	} while(g.gen(app,r));
	assert(rsltIdx == rslt.length);
}

class XmlGenStar : XmlGen {
	this(XmlGen obj, size_t low, size_t high) {
		assert(low <= high);

		this.obj = obj;
		this.low = low;
		this.high = high;
		this.i = this.low;
	}

	override bool gen(ref XmlGenOut o, ref XmlGenRnd r) {
		bool ret = false;
		for(size_t k = 0; k < this.i; ++k) {
			auto t = this.obj.gen(o, r);	
			ret = ret || t;
		}

		return ret;
	}

	override void popFront() {
		++this.i;
		if(this.i >= this.high) {
			this.i = low;
		}
	}

	XmlGen obj;
	size_t low;
	size_t high;
	size_t i;
}

class XmlGenOr : XmlGen {
	this(XmlGen[] sel) {
		assert(!sel.empty);
		this.sel = sel;
		this.i = 0;
	}

	override bool gen(ref XmlGenOut o, ref XmlGenRnd r) {
		return this.sel[i].gen(o, r);
	}

	override void popFront() {
		this.i = (this.i + i) % this.sel.length;
	}

	XmlGen[] sel;
	size_t i;
}

unittest {
	auto app = appender!string();
	XmlGenRnd r;

	auto g = new XmlGenOr([
		new XmlGenLiteral("A"),
		new XmlGenLiteral("B")
	]);

	string[] rslt = [ "A", "B" ];
	size_t rsltIdx = 0;

	bool b = g.gen(app,r);
	do {
		assert(rslt[rsltIdx++] == app.data);
		app = appender!string();
	} while(g.gen(app,r));
	assert(rsltIdx == rslt.length);
}

unittest {
	auto app = appender!string();
	XmlGenRnd r;

	auto g = new XmlGenSeq([
		new XmlGenLiteral("A"),
		new XmlGenOr([
			new XmlGenLiteral("B"),
			new XmlGenStar(
				new XmlGenLiteral("C"),
				1,3
			)
		]),
		new XmlGenOr([
			new XmlGenLiteral("D"),
			new XmlGenLiteral("E"),
		]),
	]);

	bool b = g.gen(app,r);
	do {
		log(app.data);
		app = appender!string();
	} while(g.gen(app,r));
}

class XmlGenLiteral : XmlGen {
	this(string lit) {
		this.lit = lit;
	}

	override bool gen(ref XmlGenOut o, ref XmlGenRnd r) {
		o.put(this.lit);
		return false;
	}

	string lit;
}

class XmlGenString : XmlGen {
	static this() {
		XmlGenString.chars =
			"0123456789abcdefghijklmopqrstuvxyzABCDEFGHIJKLMOPQRSTUVXYZ";
	}

	override bool gen(ref XmlGenOut o, ref XmlGenRnd r) {
		for(int i = 3; i < 10; ++i) {
			o.put(XmlGenString.chars[uniform(0, XmlGenString.chars.length, r)]);
		}
		return false;
	}

	static string chars;
}

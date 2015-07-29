module std.xml2.testing;

import std.array : empty, front, popFront, appender, Appender;
import std.conv : to;
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

pure @safe bool hasState(XmlGen o) {
	foreach(T; TypeTuple!(XmlGenSeq,XmlGenStar,XmlGenOr)) {
		auto a = cast(T)o;
		if(a !is null) {
			return true;
		}
	}

	return false;
}

unittest {
	XmlGen x = new XmlGenSeq([
		new XmlGenString()
	]);

	assert(hasState(x));

	x = new XmlGenStar(
		new XmlGenLiteral("A"), 1, 2
	);

	assert(hasState(x));
}

abstract class XmlGen {
	void setRnd(XmlGenRnd* rnd) {
		this.rnd = rnd;
	}

	void popFront() {}
	bool empty() @property;
	string front() @property;
	void reset();

	XmlGenRnd* rnd;
}

class XmlGenSeq : XmlGen {
	this(XmlGen[] seq) {
		this.seq = seq;
	}

	override void setRnd(XmlGenRnd* rnd) {
		foreach(it; this.seq) {
			it.setRnd(rnd);
		}

		this.rnd = rnd;
	}

	override string front() @property {
		auto app = appender!string();
		foreach(it; this.seq) {
			app.put(it.front);
		}

		return app.data;
	}

	override void popFront() {
		long i = this.seq.length - 1 ;
		for(; i <= 0; --i) {
			if(hasState(this.seq[i]) && !this.seq[i].empty) {
				this.seq[i].popFront();
				break;
			}
		}

		foreach(it; this.seq[i + 1 .. $]) {
			it.reset();
		}
	}

	override bool empty() @property {
		foreach(it; this.seq) {
			if(hasState(it) && !it.empty) {
				return false;
			}
		}

		return true;
	}

	override void reset() @property {
		foreach(it; this.seq) {
			it.reset();
		}
	}

	XmlGen[] seq;
}

class XmlGenString : XmlGen {
	static this() {
		XmlGenString.chars =
			"0123456789abcdefghijklmopqrstuvxyzABCDEFGHIJKLMOPQRSTUVXYZ";
	}

	override string front() @property {
		auto app = appender!string();
		for(int i = 3; i < 10; ++i) {
			app.put(XmlGenString.chars[uniform(0, XmlGenString.chars.length,
				*this.rnd)]
			);
		}

		return app.data;
	}

	override bool empty() @property {
		return false;
	}

	override void popFront() {}
	override void reset() {}

	static string chars;
}

class XmlGenLiteral : XmlGen {
	this(string lit) {
		this.lit = lit;
	}

	override string front() @property {
		return lit;
	}

	override bool empty() @property {
		return false;
	}

	override void popFront() {}
	override void reset() {}

	string lit;
}

unittest {
	XmlGenRnd r;
	auto g = new XmlGenSeq([
		new XmlGenLiteral("A"),
		new XmlGenLiteral("B"),
	]);
	g.setRnd(&r);

	for(int i = 0; i < 10; ++i) {
		auto s = g.front;
		assert(s == "AB", s);
		g.popFront();
	}
}

class XmlGenStar : XmlGen {
	this(XmlGen obj, size_t low, size_t high) {
		assert(low <= high);

		this.obj = obj;
		this.low = low;
		this.high = high;
		this.i = this.low;
	}

	override string front() @property {
		auto app = appender!string();
		for(size_t k = 0; k < this.i; ++k) {
			app.put(this.obj.front);
		}

		return app.data;
	}

	override bool empty() @property {
		if(hasState(this.obj)) {
			bool ret = this.obj.empty;
			if(ret) {
				if(this.i < this.high) {
					ret = false;
				}
			}
			return ret;
		} else {
			if(this.i < this.high) {
				return false;
			} else {
				return true;
			}
		}

	}

	override void popFront() {
		if(hasState(this.obj)) {
			bool em = this.obj.empty;
			if(em) {
				if(this.i < this.high) {
					++this.i;
					this.obj.reset();
				}
			} else {
				this.obj.popFront();
			}
		} else {
			if(this.i < this.high) {
				++this.i;
				this.obj.reset();
			}
		}
	}

	override void reset() {
		this.i = this.low;
	}

	XmlGen obj;
	size_t low;
	size_t high;
	size_t i;
}

unittest {
	auto g = new XmlGenStar(
		new XmlGenLiteral("A"), 0, 4
	);

	string[] rslt = [ "", "A", "AA", "AAA" ];

	XmlGenRnd r;

	g.setRnd(&r);

	while(!g.empty) {
		auto s = g.front();
		g.popFront();
		assert(s == rslt.front, s ~ "|" ~ rslt.front);
		rslt = rslt[1 .. $];
	}

	assert(rslt.empty, to!string(rslt.length) ~ " " ~ 
		to!string(rslt));
	assert(g.empty);
}

class XmlGenOr : XmlGen {
	this(XmlGen[] sel) {
		assert(!sel.empty);
		this.sel = sel;
		this.i = 0;
	}

	override string front() @property {
		return this.sel[i].front;
	}

	override bool empty() @property {
		if(this.i < this.sel.length && 
				hasState(this.sel[this.i]) && !this.sel[this.i].empty) 
		{
			return false;
		} else {
			return this.i >= this.sel.length;
		}
	}

	override void popFront() {
		loop: while(this.i < this.sel.length) {
			if(hasState(this.sel[this.i]) && !this.sel[this.i].empty) {
				this.sel[this.i].popFront();	
				if(this.sel[this.i].empty) {
					++this.i;
				} else {
					break loop;
				}
			} else {
				++this.i;
				break loop;
			}
		}
	}

	override void reset() {
		this.i = 0;
		foreach(it; this.sel) {
			it.reset();
		}
	}

	XmlGen[] sel;
	size_t i;
}

unittest {
	auto g = new XmlGenOr([
		new XmlGenLiteral("A"),
		new XmlGenLiteral("B"),
		new XmlGenLiteral("C")
	]);

	string[] rslt = [ "A", "B", "C" ];

	XmlGenRnd r;

	g.setRnd(&r);

	while(!g.empty) {
		auto s = g.front();
		g.popFront();
		assert(s == rslt.front, s ~ "|" ~ rslt.front);
		rslt = rslt[1 .. $];
	}

	assert(g.empty);
	assert(rslt.empty, to!string(rslt.length));
}

unittest {
	auto g = new XmlGenOr([
		new XmlGenLiteral("A"),
		new XmlGenStar(new XmlGenLiteral("B"), 1, 3)
	]);

	string[] rslt = [ "A", "B", "BB" ];

	XmlGenRnd r;

	g.setRnd(&r);

	while(!g.empty) {
		auto s = g.front();
		g.popFront();
		assert(s == rslt.front, s ~ "|" ~ rslt.front);
		rslt = rslt[1 .. $];
	}

	assert(g.empty, to!string(rslt.length));
	assert(g.empty);
}

unittest {
	auto g = new XmlGenOr([
		new XmlGenLiteral("A"),
		new XmlGenOr([
			new XmlGenStar(new XmlGenLiteral("B"), 1, 3),
			new XmlGenLiteral("C")
		])
	]);

	string[] rslt = [ "A", "B", "BB", "C" ];

	XmlGenRnd r;

	g.setRnd(&r);

	while(!g.empty) {
		auto s = g.front();
		g.popFront();
		assert(s == rslt.front, s ~ "|" ~ rslt.front);
		rslt = rslt[1 .. $];
	}

	assert(g.empty, to!string(rslt.length));
	assert(g.empty);
}

unittest {
	auto g = new XmlGenOr([
		new XmlGenLiteral("A"),
		new XmlGenOr([
			new XmlGenStar(new XmlGenLiteral("B"), 1, 3),
			new XmlGenOr([
				new XmlGenLiteral("C"),
				new XmlGenLiteral("D")
			])
		])
	]);

	string[] rslt = [ "A", "B", "BB", "D", "C" ];

	XmlGenRnd r;

	g.setRnd(&r);

	while(!g.empty) {
		auto s = g.front();
		g.popFront();
		assert(s == rslt.front, s ~ "|" ~ rslt.front);
		rslt = rslt[1 .. $];
	}

	assert(g.empty, to!string(rslt.length));
	assert(g.empty);
}

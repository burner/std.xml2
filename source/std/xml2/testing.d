module std.xml2.testing;

import std.array : empty, front, popFront, appender, Appender;
import std.conv : to;
import std.meta;
import std.range.primitives : ElementType, ElementEncodingType;
import std.random : Random, uniform;
import std.experimental.logger;
import std.string : indexOf;

alias TestInputTypes = AliasSeq!(
	string, wstring, dstring,
	char[], wchar[], dchar[],
	//immutable(ubyte)[], immutable(ushort)[], immutable(uint)[],
	CharInputRange!string, CharInputRange!wstring, CharInputRange!dstring
);

alias TestInputArray = AliasSeq!(
	string, wstring, dstring,
	char[], wchar[], dchar[]
	//immutable(ubyte)[], immutable(ushort)[], immutable(uint)[]
);

alias TestInputRanges = AliasSeq!(
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

alias XmlGenRnd = Random;

pure @safe bool hasState(XmlGen o) {
	auto a = cast(XmlGenSeq)o;
	if(a !is null) {
		if(a.hasStateM()) {
			return true;
		}	
	}

	foreach(T; AliasSeq!(XmlGenStar,XmlGenOr)) {
		auto b = cast(T)o;
		if(b !is null) {
			return true;
		}
	}

	return false;
}

unittest {
	XmlGen x = new XmlGenSeq([
		new XmlGenString()
	]);

	assert(!hasState(x));

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
	XmlGen save() @property;

	XmlGenRnd* rnd;
}

class XmlGenSeq : XmlGen {
	this(XmlGen[] seq) {
		this.seq = seq;
		this.i = this.seq.length - 1;
		for(; this.i != -1; --this.i) {
			if(hasState(this.seq[this.i])) {
				break;
			}
		}
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

	bool hasStateM() pure @safe {
		foreach(it; this.seq) {
			if(hasState(it)) {
				return true;
			}
		}

		return false;
	}

	override void popFront() {
		for(long j = this.seq.length - 1; j != -1; --j) {
			if(hasState(this.seq[j])) {
				if(!this.seq[j].empty) {
					this.seq[j].popFront();
					if(this.seq[j].empty) {
						continue;
					}
					for(long k = j + 1; k < this.seq.length; ++k) {
						this.seq[k].reset();
					}
					break;
				}
			}
		}
	}

	override bool empty() @property {
		for(long j = 0; j < this.seq.length; ++j) {
			if(hasState(this.seq[j])) {
				if(!this.seq[j].empty) {
					return false;
				} else {
					return true;
				}
			}
		}
		return true;
	}

	override void reset() @property {
		foreach(it; this.seq) {
			it.reset();
		}
	}

	override XmlGen save() @property {
		XmlGen[] da = new XmlGen[this.seq.length];
		foreach(idx, it; this.seq) {
			da[idx] = it.save;
		}

		return new XmlGenSeq(da);
	}

	XmlGen[] seq;
	long i;
}

class XmlGenChar : XmlGen {
	static this() {
		XmlGenChar.chars =
			"0123456789abcdefghijklmopqrstuvxyzABCDEFGHIJKLMOPQRSTUVXYZ-'()+," ~
			"./:=?;!*#@$_%]";
	}

	this(string ex = "") {
		this.exclude = ex;
		this.popFront();
	}

	override void popFront() {
		while(true) {
			auto c = XmlGenChar.chars[uniform(0, XmlGenChar.chars.length)];
			if(this.exclude.indexOf(c) == -1) {
				auto app = appender!string();
				app.put(c);
				this.frontValue = app.data;
				break;
			}
		}
	}

	override string front() @property {
		return this.frontValue;
	}

	override bool empty() @property {
		return false;
	}

	override XmlGen save() @property {
		return new XmlGenChar(this.exclude);
	}

	override void reset() {}

	static string chars;

	string frontValue;
	string exclude;
}

class XmlGenCharRange : XmlGen {
	this(dchar be, dchar en) {
		this.be = be;
		this.en = en;
	}

	dchar be;
	dchar en;

	override bool empty() @property {
		return false;
	}

	override void popFront() {}

	override string front() @property {
		auto app = appender!string();
		app.put(uniform(this.be, this.en));

		return app.data;
	}

	override void reset() {}

	override XmlGen save() @property {
		return new XmlGenCharRange(this.be, this.en);
	}
}

class XmlGenString : XmlGen {
	static this() {
		XmlGenString.chars =
			"0123456789abcdefghijklmopqrstuvxyzABCDEFGHIJKLMOPQRSTUVXYZ";
	}

	this() {
		this.popFront();
	}

	this(string ex = "") {
		this.exclude = ex;
		this.popFront();
	}

	override void popFront() {
		auto app = appender!string();
		const auto l = uniform(3, 10);
		while(true && app.data.length < l) {
			auto c = XmlGenString.chars[uniform(0, XmlGenString.chars.length)];
			if(this.exclude.indexOf(c) == -1) {
				app.put(c);
			}
		}

		this.frontValue = app.data;
	}

	override string front() @property {
		return this.frontValue;
	}

	override bool empty() @property {
		return false;
	}

	override void reset() {}

	override XmlGen save() @property {
		return new XmlGenString();
	}

	static string chars;

	string frontValue;
	string exclude;
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

	override XmlGen save() @property {
		return new XmlGenLiteral(this.lit);
	}

	string lit;
}

unittest {
	auto g = new XmlGenSeq([
		new XmlGenOr([
			new XmlGenLiteral("A"),
			new XmlGenLiteral("B"),
		]),
		new XmlGenOr([
			new XmlGenLiteral("C"),
			new XmlGenLiteral("D"),
		])
	]);

	string[] rslt = [ "AC", "AD", "BC", "BD" ];

	long i = 0;
	while(!g.empty) {
		auto s = g.front();
		g.popFront();
		assert(s == rslt.front, s ~ "!=" ~ rslt.front ~ " | " 
			~ to!string(i));
		rslt = rslt[1 .. $];
		++i;
	}

	assert(rslt.empty, to!string(rslt.length) ~ " " ~ 
		to!string(rslt));
	assert(g.empty);
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
		return this.i >= this.high;
	}

	override void popFront() {
		if(hasState(this.obj)) {
			this.obj.popFront();
			bool em = this.obj.empty;
			if(em) {
				++this.i;
				this.obj.reset();
			}
		} else {
			++this.i;
			this.obj.reset();
		}
	}

	override void reset() {
		this.i = this.low;
		this.obj.reset();
	}

	override XmlGen save() @property {
		return new XmlGenStar(this.obj.save, this.low, this.high);
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
		this.isEmpty = false;
	}

	override string front() @property {
		return this.sel[i].front;
	}

	override bool empty() @property {
		return this.isEmpty;
	}

	override void popFront() {
		if(hasState(this.sel[this.i]) && !this.sel[this.i].empty) {
			this.sel[this.i].popFront();
			if(this.sel[this.i].empty) {
				++this.i;
				this.isEmpty = this.i == this.sel.length;
			} else {
				this.isEmpty = false;
			}
		} else {
			++this.i;
			this.isEmpty = this.i == this.sel.length;
		}
	}

	override void reset() {
		foreach(it; this.sel) {
			it.reset();
		}
		this.isEmpty = false;
		this.i = 0;
	}

	override XmlGen save() @property {
		XmlGen[] da = new XmlGen[this.sel.length];
		foreach(idx, it; this.sel) {
			da[idx] = it.save;
		}

		return new XmlGenOr(da);
	}

	XmlGen[] sel;
	size_t i;
	bool isEmpty;
}

unittest {
	auto g = new XmlGenOr([
		new XmlGenLiteral("A"),
		new XmlGenLiteral("B"),
		new XmlGenLiteral("C")
	]);

	string[] rslt = [ "A", "B", "C" ];

	while(!g.empty) {
		auto s = g.front();
		g.popFront();
		assert(s == rslt.front, s ~ "|" ~ rslt.front);
		rslt = rslt[1 .. $];
	}

	assert(rslt.empty, to!string(rslt.length));
	assert(g.empty);
}

unittest {
	auto g = new XmlGenOr([
		new XmlGenLiteral("A"),
		new XmlGenStar(new XmlGenLiteral("B"), 1, 3)
	]);

	string[] rslt = [ "A", "B", "BB" ];

	while(!g.empty) {
		auto s = g.front();
		g.popFront();
		assert(s == rslt.front, s ~ "|" ~ rslt.front);
		rslt = rslt[1 .. $];
	}

	assert(rslt.empty, to!string(rslt.length));
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

	while(!g.empty) {
		auto s = g.front();
		g.popFront();
		assert(s == rslt.front, s ~ "|" ~ rslt.front);
		rslt = rslt[1 .. $];
	}

	assert(rslt.empty, to!string(rslt.length));
	assert(g.empty);
}

unittest {
	auto g = new XmlGenOr([
		new XmlGenLiteral("A"),
		new XmlGenOr([
			new XmlGenLiteral("C"),
			new XmlGenLiteral("D")
		]),
		new XmlGenLiteral("B")
	]);

	string[] rslt = [ "A", "C", "D", "B"];

	while(!g.empty) {
		auto s = g.front();
		g.popFront();
		assert(s == rslt.front, s ~ "|" ~ rslt.front);
		rslt = rslt[1 .. $];
	}

	assert(rslt.empty, to!string(rslt.length));
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

	string[] rslt = [ "A", "B", "BB", "C", "D" ];

	while(!g.empty) {
		auto s = g.front();
		g.popFront();
		assert(s == rslt.front, s ~ "|" ~ rslt.front);
		rslt = rslt[1 .. $];
	}

	assert(rslt.empty, to!string(rslt.length));
	assert(g.empty);
}

unittest {
	auto g = new XmlGenOr([
		new XmlGenStar(
			new XmlGenOr([
				new XmlGenLiteral("A"),
				new XmlGenLiteral("B")
			]), 
			1, 3
		),
		new XmlGenLiteral("C")
	]);

	string[] rslt = [ "A", "B", "AA", "BB", "C" ];

	while(!g.empty) {
		auto s = g.front();
		g.popFront();
		assert(s == rslt.front, s ~ " != " ~ rslt.front);
		rslt = rslt[1 .. $];
	}

	assert(rslt.empty, to!string(rslt.length));
	assert(g.empty);
}

unittest {
	auto g = new XmlGenStar(
		new XmlGenOr([
			new XmlGenStar(
				new XmlGenLiteral("A"), 1, 3
			),
			new XmlGenLiteral("B")
		]), 
		1, 3
	);

	string[] rslt = [ "A", "AA", "B", "AA", "AAAA", "BB" ];

	XmlGenRnd r;
	g.setRnd(&r);

	while(!g.empty) {
		auto s = g.front();
		g.popFront();
		assert(s == rslt.front, s ~ " != " ~ rslt.front);
		rslt = rslt[1 .. $];
	}

	assert(rslt.empty, to!string(rslt.length));
	assert(g.empty);
}

unittest {
	auto g = new XmlGenSeq([
		new XmlGenLiteral("A"),
		new XmlGenOr([
			new XmlGenLiteral("B"),
			new XmlGenStar(
				new XmlGenLiteral("C"), 1, 3
			),
			new XmlGenSeq([
				new XmlGenLiteral("D"),
				new XmlGenLiteral("E")
			])
		]),
		new XmlGenSeq([
			new XmlGenLiteral("F"),
			new XmlGenOr([
				new XmlGenLiteral("G"),
				new XmlGenLiteral("H")
			])
		])
	]);

	string[] rslt = [ "ABFG", "ABFH","ACFG", "ACFH", "ACCFG", "ACCFH",
		"ADEFG", "ADEFH"];

	XmlGenRnd r;
	g.setRnd(&r);

	while(!g.empty) {
		auto s = g.front();
		g.popFront();
		assert(s == rslt.front, s ~ " != " ~ rslt.front);
		rslt = rslt[1 .. $];
	}

	assert(rslt.empty, to!string(rslt.length));
	assert(g.empty);
}

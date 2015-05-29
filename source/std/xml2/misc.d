module std.xml2.misc;

ptrdiff_t indexOfX(C1,C2)(C1 c1, C2 c2) {
	import std.traits : isSomeString;
	static if(isSomeString!C1) {
		static import std.string;
		return std.string.indexOf(c1, c2);
	} else {
		return indexOfImpl(c1, c2);
	}
}

private ptrdiff_t indexOfImpl(C1,C2)(C1 c1, C2 c2) { // Only works for ascii
	import std.traits : isArray;
	static if(isArray!C2) {
		size_t i = 0;
		outer: for(; i < c1.length; ++i) {
			if(c1.length - i >= c2.length) {
				foreach(jdx, jt; c2) {
					if(jt != c1[i+jdx]) {
						continue outer;
					}
				}

				return i;
			} else {
				break;
			}
		}

		return -1;
	} else {
		import std.range.primitives : ElementType;

		ElementType!C1 a = cast(ElementType!C1)c2;
		foreach(idx, it; c1) {
			if(it == a) {
				return idx;
			}
		}

		return -1;
	}
}

unittest {
	import std.conv : to;
	dstring a = "Hällo";
	string b = "ä";

	assert(indexOfX(a, b) == 1);

	string a2 = "xml ?>";
	assert(indexOfX(cast(immutable(ubyte)[])a2, "xml ") == 0);
	auto idx = indexOfX(cast(immutable(ubyte)[])a2, "?>");
	assert(idx == 4, to!string(idx));

	idx = indexOfX(" xml", "xml");
	assert(idx == 1);
	idx = indexOfX("xml", "xml");
	assert(idx == 0);
	idx = indexOfX("xml", "xm");
	assert(idx == 0);
	idx = indexOfX("ml", "xml");
	assert(idx == -1);
}

string toStringX(C)(C c) {
	import std.traits : hasMember, isSomeString, Unqual;
	import std.conv : to;
	static if(isSomeString!C) {
		return to!string(c);
	} else {
		import std.range.primitives : ElementType;
		import std.exception : assumeUnique;

		static if(hasMember!(C, "ptr")) {
			static if(is(Unqual!(ElementType!C) == ubyte)) {
				return assumeUnique((cast(char*)c.ptr)[0 .. c.length]);
			} else static if(is(Unqual!(ElementType!C) == ushort)) {
				return to!string((cast(wchar*)c.ptr)[0 .. c.length]);
			} else static if(is(Unqual!(ElementType!C) == uint)) {
				return to!string((cast(dchar*)c.ptr)[0 .. c.length]);
			}
		} else {
			//static assert(false, C.stringof);
			return "";
		}
	}
}

import std.range.primitives : isInputRange;

struct ForwardRangeInput(T, size_t bufSize) if(isInputRange!T) {
	import std.range.primitives : ElementEncodingType;
	import std.traits : Unqual;

	alias InputType = Unqual!(ElementEncodingType!(T));
	
	private InputType[bufSize] buf;
	private size_t idx;
	private T input;

	this(T input) {
		this.input = input;
		this.idx = 0;
	}

	@property auto front() {
		import std.array : front;
		if(this.idx > 0) {
			return this.buf.front;
		} else {
			return this.input.front;
		}
	}

	void popFront() {
		import std.array : popFront;
		if(this.idx > 0) {
			for(size_t i = 1; i < this.idx; ++i) {
				this.buf[i-1] = this.buf[i];
			}
			--this.idx;
		} else {
			this.input.popFront();
		}
	}

	@property bool empty() {
		import std.array : empty;
		return this.idx == 0 && this.input.empty;
	}

	void prefetch() {
		import std.array : empty, front, popFront;
		import std.traits : isArray;
		for(; this.idx < buf.length && !this.input.empty; ++this.idx) {
			static if(isArray!T) {
				this.buf[this.idx] = this.input[0];
			} else {
				this.buf[this.idx] = this.input.front;
			}
			this.input.popFront();
		}	
	}

	auto getBuffer() {
		return this.buf[0 .. idx];
	}

	string toString() {
		import std.array : appender;
		auto app = appender!string();

		while(!this.empty) {
			auto it = this.front;
			static if(is(InputType == ubyte)) {
				app.put(cast(char)it);
			} else static if(is(InputType == ushort)) {
				app.put(cast(wchar)it);
			} else static if(is(InputType == uint)) {
				app.put(cast(dchar)it);
			}

			this.popFront();
		}

		return app.data;
	}
}

unittest {
	import std.xml2.testing : CharInputRange;
	import std.algorithm.comparison : min, equal;
	import std.array : front;
	import std.typecons : TypeTuple;

	auto str = "Hello world";

	foreach(Cnt; TypeTuple!(1,2,3,4,5,6,7,8,9,10,11,12,13,1024)) {
		auto input = CharInputRange!(string)("Hello world");
		auto forward = ForwardRangeInput!(typeof(input), Cnt)(input);
		auto forward2 = ForwardRangeInput!(typeof(input), Cnt)(input);

		for(size_t i = 0; i < str.length; ++i) {
			auto strS = str[i .. min(i+Cnt, $)];

			assert(!forward.empty);
			assert(forward.front == strS.front);

			forward.prefetch();

			auto buf = forward.getBuffer();

			assert(buf.length == strS.length);
			assert(equal(buf, strS));

			forward.popFront();
		}

		assert(equal(forward2, str));
	}
}

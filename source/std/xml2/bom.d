module std.xml2.bom;

import std.typecons;
import std.conv;
import std.range;
import std.array;
import std.traits;

unittest
{
	static assert(isForwardRange!(ubyte[]));
}

/** Definitions of common Byte Order Marks.
The elements of the $(D enum) can used as indices into $(D bomTable) to get
matching $(D BOMSeq).
*/
enum BOM
{
    none      = 0,  /// no BOM was found
    utf32be   = 1,  /// [0x00, 0x00, 0xFE, 0xFF]
    utf32le   = 2,  /// [0xFF, 0xFE, 0x00, 0x00]
    utf7      = 3,  /*  [0x2B, 0x2F, 0x76, 0x38]
                        [0x2B, 0x2F, 0x76, 0x39],
                        [0x2B, 0x2F, 0x76, 0x2B],
                        [0x2B, 0x2F, 0x76, 0x2F],
                        [0x2B, 0x2F, 0x76, 0x38, 0x2D]
                    */
    utf1      = 8,  /// [0xF7, 0x64, 0x4C]
    utfebcdic = 9,  /// [0xDD, 0x73, 0x66, 0x73]
    scsu      = 10, /// [0x0E, 0xFE, 0xFF]
    bocu1     = 11, /// [0xFB, 0xEE, 0x28]
    gb18030   = 12, /// [0x84, 0x31, 0x95, 0x33]
    utf8      = 13, /// [0xEF, 0xBB, 0xBF]
    utf16be   = 14, /// [0xFE, 0xFF]
    utf16le   = 15  /// [0xFF, 0xFE]
}

/// The type stored inside $(D bomTable).
alias BOMSeq = Tuple!(BOM, "schema", ubyte[], "sequence");

/** Mapping of a byte sequence to $(B Byte Order Mark (BOM))
*/
immutable bomTable = [
    BOMSeq(BOM.none, new ubyte[0]),
    BOMSeq(BOM.utf32be, to!(ubyte[])([0x00, 0x00, 0xFE, 0xFF])),
    BOMSeq(BOM.utf32le, to!(ubyte[])([0xFF, 0xFE, 0x00, 0x00])),
    BOMSeq(BOM.utf7, to!(ubyte[])([0x2B, 0x2F, 0x76, 0x39])),
    BOMSeq(BOM.utf7, to!(ubyte[])([0x2B, 0x2F, 0x76, 0x2B])),
    BOMSeq(BOM.utf7, to!(ubyte[])([0x2B, 0x2F, 0x76, 0x2F])),
    BOMSeq(BOM.utf7, to!(ubyte[])([0x2B, 0x2F, 0x76, 0x38, 0x2D])),
    BOMSeq(BOM.utf7, to!(ubyte[])([0x2B, 0x2F, 0x76, 0x38])),
    BOMSeq(BOM.utf1, to!(ubyte[])([0xF7, 0x64, 0x4C])),
    BOMSeq(BOM.utfebcdic, to!(ubyte[])([0xDD, 0x73, 0x66, 0x73])),
    BOMSeq(BOM.scsu, to!(ubyte[])([0x0E, 0xFE, 0xFF])),
    BOMSeq(BOM.bocu1, to!(ubyte[])([0xFB, 0xEE, 0x28])),
    BOMSeq(BOM.gb18030, to!(ubyte[])([0x84, 0x31, 0x95, 0x33])),
    BOMSeq(BOM.utf8, to!(ubyte[])([0xEF, 0xBB, 0xBF])),
    BOMSeq(BOM.utf16be, to!(ubyte[])([0xFE, 0xFF])),
    BOMSeq(BOM.utf16le, to!(ubyte[])([0xFF, 0xFE]))
];

/** Returns a $(D BOMSeq) for a given $(D input).
If no $(D BOM) is present the $(D BOMSeq) for $(D BOM.none) is
returned. The $(D BOM) sequence at the beginning of the range will
not be comsumed from the passed range. If you pass a reference type
range make sure that $(D save) creates a deep copy.

Params:
    input = The sequence to check for the $(D BOM)

Returns:
    the found $(D BOMSeq) corresponding to the passed $(D input).
*/
immutable(BOMSeq) getBOM(Range)(Range input)
        if(isForwardRange!Range && is(Unqual!(ElementType!(Range)) == ubyte))
{
    import std.algorithm.searching : startsWith;
    foreach (it; bomTable[1 .. $])
    {
        if (startsWith(input.save, it.sequence))
        {
            return it;
        }
    }

    return bomTable[0];
}

///
unittest
{
    import std.format : format;

    // This creates a dstring "Hello World" with a BOM
    auto ts = (cast(dstring)to!(ubyte[])([0xFF, 0xFE, 0x00, 0x00])) ~
        "Hello World"d;

    auto entry = getBOM(cast(ubyte[])ts);
    assert(entry.schema == BOM.utf32le);
}

unittest
{
    import std.format : format;

    foreach (idx, it; bomTable)
    {
        auto s = it[1] ~ cast(ubyte[])"hello world";
        auto i = getBOM(s);
        assert(i[0] == bomTable[idx][0]);

        if (idx < 4 || idx > 7) // get around the multiple utf7 bom's
        {
            assert(i[0] == BOM.init + idx);
            assert(i[1] == it[1]);
        }
    }
}

unittest
{
    struct BOMInputRange
    {
        immutable(ubyte[]) arr;
        size_t idx = 0;

        @property ubyte front()
        {
            return this.arr[idx];
        }

        @property bool empty()
        {
            return this.idx == this.arr.length;
        }

        void popFront()
        {
            ++this.idx;
        }

        @property typeof(this) save()
        {
            return this;
        }
    }

    static assert( isInputRange!BOMInputRange);
    static assert(!isArray!BOMInputRange);

    ubyte[] dummyEnd = [0,0,0,0];

    foreach (idx, it; bomTable[1 .. $])
    {
        {
            auto ir = BOMInputRange(it.sequence);

            auto b = getBOM(ir);
            assert(b.schema == it.schema);
            assert(ir.arr == it.sequence);
        }

        {
            auto noBom = it.sequence[0 .. 1].dup ~ dummyEnd;
            size_t oldLen = noBom.length;
            assert(oldLen - 4 < it.sequence.length);

            auto ir = BOMInputRange(noBom.idup);
            auto b = getBOM(ir);
            assert(b.schema == BOM.none);
            assert(noBom.length == oldLen);
        }
    }
}

private void wstringLEtoBE(ushort[] arr) {
	wstringEndian!(0xDC00, 0xDFFF)(arr);
}

private void wstringBEtoLE(ushort[] arr) {
	wstringEndian!(0xD800, 0xDBFF)(arr);
}

private void wstringEndian(int l, int h)(ushort[] arr) {
	for(size_t i = 0; i < arr.length - 1;) {
		if(arr[i] > l && arr[i] < h) {
			auto t = arr[i];	
			arr[i] = arr[i + 1];
			arr[i + 1] = t;
			i += 2;
		} else {
			++i;
		}
	}
}

private void dstringToOtherEndian(uint[] arr) {
	import core.bitop : bswap;
	for(size_t i = 0; i < arr.length; ++i) {
		arr[i] = bswap(arr[i]);
	}
}

S readTextWithBOM(S = string, R)(R name)
    if (isSomeString!S &&
        (isInputRange!R && isSomeChar!(ElementEncodingType!R) || isSomeString!R) &&
        !isConvertibleToString!R)
{
    import std.utf : validate;
    import std.file : read;
    static auto trustedCast(T,R)(R buf) @trusted { return cast(T)buf; }
    ubyte[] asUbytes = trustedCast!(ubyte[])(read(name));

	auto bom = getBOM(asUbytes[]);
	S ret;

	switch(bom.schema) 
	{
		case BOM.none:
			ret = to!(S)(
				trustedCast!(string)(asUbytes)
			);
			break;
		case BOM.utf8:
			ret = to!(S)(
				trustedCast!(string)(asUbytes[bom.sequence.length ..  $])
			);
			break;
		case BOM.utf16le:
		{
			auto t = asUbytes[bom.sequence.length .. $];
			version(BigEndian) {
				wstringLEtoBE(trustedCast!(ushort[])(t));
			}
			ret = to!S(trustedCast!(wstring)(t));
			break;
		}
		case BOM.utf16be: 
		{
			auto t = asUbytes[bom.sequence.length .. $];
			version(LittleEndian) {
				wstringBEtoLE(trustedCast!(ushort[])(t));
			}
			ret = to!S(trustedCast!(wstring)(t));
			break;
		}
		case BOM.utf32le:
		{
			auto t = asUbytes[bom.sequence.length .. $];
			version(BigEndian) {
				dstringToOtherEndian(trustedCast!(uint[])(t));
			}
			ret = to!S(trustedCast!(dstring)(t));
			break;
		}
		case BOM.utf32be:
		{
			auto t = asUbytes[bom.sequence.length .. $];
			version(LittleEndian) {
				dstringToOtherEndian(trustedCast!(uint[])(t));
			}
			ret = to!S(trustedCast!(dstring)(t));
			break;
		}
		default:
			assert(false);
	}
	//validate(ret);
    return ret;
}

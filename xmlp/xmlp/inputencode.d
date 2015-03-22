
/**
Authors: Michael Rynn
Licence: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.

Distributed under the Boost Software License, Version 1.0.
Part of xmlp.xmlp package reimplementation of std.xml.

Provides character decoding support to module xmlp.xmlp.charinputs

Templates RecodeChar(T), RecodeWChar(T) and RecodeDChar(T) take either a delegate, function
or an InputRange with a pull method,
which makes it not an InputRange, but earlier versions used InputRange.

----
//The functions return whether or not a request for character type succeeded.

	bool delegate(ref T inChar);
	bool function(ref T inChar);
	bool pull(ref T inChar);

//  Input Range implementation of pull.
bool pull(ref SourceCharType c)
{
	if (empty)
		return false;
	c = front
	popFront();
}

// these either return a character or tell the caller it cannot be done.
alias bool delegate(ref char c)  Char8pull;
alias bool delegate(ref wchar c) Char16pull;
alias bool delegate(ref dchar c) Char32pull;

// RecodeDgFn.  Each function type uses the corresponding delegate
alias bool function(Char8pull src, ref dchar c) Recode8Fn;
alias bool function(Char16pull src, ref dchar c) Recode16Fn;
alias bool function(Char32pull src, ref dchar c) Recode32Fn;

---
*/
module xmlp.xmlp.inputencode;

import core.exception;
import std.system;
import std.stream;
import std.conv;
import std.string;
import std.traits;
import std.stdint;
import alt.zstring;
import std.exception;

/// The character sequence was broken unexpectedly, or had an illegal encoding character.
class CharSequenceError :  Exception
{
    this(string s)
    {
        super(s);
    }
};

/// Throw a CharSequenceError for invalid character.
void invalidCharacter(dchar c)
{
    string msg = format("Invalid character {%x}", c);

    throw new CharSequenceError(msg);
}

/+void indexError()
{
    throw new CharSequenceError("index past array length");
}
+/

/// Throw a CharSequenceError for broken UTF sequence
void breakInSequence()
{
    throw new CharSequenceError("Broken character sequence");
}

/// home made method for byte swapping
align(1) struct cswap
{
    char c0;
    char c1;
}

/// Home made byte swapper for 16 bit byte order reversal
align(1) union wswapchar
{
    cswap c;
    wchar w0;
}

/// Home made 32 bit byte swapper
align(1) struct cswap4
{
    char c0;
    char c1;
    char c2;
    char c3;
}
/// Home made byte swapper for 32 bit byte order reversal
align(1) struct dswapchar
{
    cswap4  c;
    dchar   d0;
}


private static const wstring windows1252_map =
    "\u20AC\uFFFD\u201A\u0192\u201E\u2026\u2020\u2021"
    "\u02C6\u2030\u0160\u2039\u0152\uFFFD\u017D\uFFFD"
    "\uFFFD\u2018\u2019\u201C\u201D\u2022\u2103\u2014"
    "\u02DC\u2122\u0161\u203A\u0153\uFFFD\u017E\u0178";



// Keeping the template InputRange (pull) version as well.

template isPullRange(R)
{
    enum bool isPullRange = is(typeof(
                                   {
                                       R r;             // can define a range object
    if (r.empty) {}  // can test for empty
r.popFront();          // can invoke next
auto h = r.front; // can get the front of the range
bool gotit = r.pull(h); // can use pull to do all at once
                               }
                               ()));
}


/** Mass buffer decode for char to dchar.
Fills dchar[] array, till dchar[] array is full, or src array is exhausted, or has not enough
characters to finish a UTF sequence.  Returns number of source characters consumed, and
number of characters converted, 
*/

uintptr_t decode_char(const(char)[] src, dchar[] dest, ref uintptr_t pos )
{
    size_t ix = pos;
    size_t destix = 0;

    immutable last = src.length;

    while (destix < dest.length)
    {
        if (ix >= last)
            break;   // exhausted source

        dchar d32 = src[ix++];

        if (d32 < 0x80)
        {
            dest[destix++] = d32;
            continue;
        }

        if (d32 < 0xC0)
        {
            invalidCharacter(d32);
        }

        int tails = void;
        if (d32 < 0xE0)
        {
            tails = 1;
            d32 = d32 & 0x1F;
        }
        else if (d32 < 0xF0)
        {
            tails = 2;
            d32 = d32 & 0x0F;
        }
        else if (d32 < 0xF8)
        {
            tails = 3;
            d32 = d32 & 0x07;
        }
        else if (d32< 0xFC)
        {
            tails = 4;
            d32 = d32  & 0x03;
        }
        else
        {
            invalidCharacter(d32);
        }
        if (ix + tails > src.length)
        {
			pos = ix-1;
			return destix;
		}
        while(tails--)
        {
            d32 = (d32 << 6) + (src[ix++] & 0x3F);
        }
        dest[destix++] = d32;
    }
    pos = ix;
    return destix;
}
/** Mass buffer decode for wchar to dchar.
Fills dchar[] array, till dchar[] array is full, or src array is exhausted, starting at pos
return number of dest array characters filled, and number of source characters converted.
*/
size_t decode_wchar(const(wchar)[] src, dchar[] dest, ref size_t pos )
{
    size_t ix = pos;
    size_t destix = 0;

    immutable last = src.length;

    while (destix < dest.length)
    {
        if (ix >= last)
            break; // exhausted source
        dchar d32 = src[ix++];

        if (d32 < 0xD800 || d32 >= 0xE000)
        {
            dest[destix++] = d32;
            continue;
        }
        if (ix >= last)
        {
			pos = ix-1;
			return destix;
		}
        dest[destix++] = 0x10000 + ((d32 & 0x3FF) << 10) + ( src[ix++] & 0x3FF);
    }
    pos = ix;
    return destix;
}

/** Template for 1 byte character decoders,
	for PullRange, Delegate, or Functions to get next source character.
*/

template  RecodeChar(T)
{

    // Not using table lookup
    bool recode_UTF8(T rgc, ref dchar c)
    {
        char d8;
        static if(isDelegate!(T) || isFunctionPointer!(T))
        {
            if (!rgc(d8))
                return false; // empty is ok
        }
        else static if(isPullRange!(T))
        {
            if (!rgc.pull(d8))
                return false; // empty is ok
        }
        else
        {
            assert(0);
        }
        dchar d = d8;
        if (d < 0x80)
        {
            c = d;
            return true;
        }

        if (d < 0xC0)
        {
            invalidCharacter(d);
        }

        int tails = void;
        if (d < 0xE0)
        {
            tails = 1;
            d = d & 0x1F;
        }
        else if (d < 0xF0)
        {
            tails = 2;
            d = d & 0x0F;
        }
        else if (d < 0xF8)
        {
            tails = 3;
            d = d & 0x07;
        }
        else if (d < 0xFC)
        {
            tails = 4;
            d = d & 0x03;
        }
        else
        {
            invalidCharacter(d);
        }
        while(tails--)
        {
            static if(isDelegate!(T) || isFunctionPointer!(T))
            {
                if (!rgc(d8))
                    breakInSequence();
            }
            else static if(isPullRange!(T))
            {
                if (!rgc.pull(d8))
                    breakInSequence();
            }
            d = (d << 6) + (d8 & 0x3F);
        }
        c = d;
        return true;
    }

    /// Windows 1252 8 bit recoding
    bool recode_windows1252(T rgc, ref dchar c)
    {
        char d8;

        static if(isDelegate!(T) || isFunctionPointer!(T))
        {
            if (!rgc(d8))
                return false; // empty is ok
        }
        else static if (isPullRange!(T))
        {
            if (!rgc.pull(d8))
                return false; // empty is ok
        }
        dchar test = d8;
        dchar result = (test >= 0x80 && test < 0xA0) ? windows1252_map[test-0x80] : test;
        if (result == 0xFFFD)
        {
            return false;
        }
        else
        {
            c = result;
            return true;
        }
    }
    /// For Latin 8 bit recoding
    bool recode_latin1(T rgc, ref dchar c)
    {
        char d8;
        static if(isDelegate!(T) || isFunctionPointer!(T))
        {
            if (!rgc(d8))
                return false; // empty is ok
        }
        else static if (isPullRange!(T))
        {
            if (!rgc.pull(d8))
                return false; // empty is ok
        }
        c = d8;
        return true;
    }

    /// For plain ASCII 7-bit recoding
    bool recode_ascii(T rgc, ref dchar c)
    {
        char d8;
        static if(isDelegate!(T) || isFunctionPointer!(T))
        {
            if (!rgc(d8))
                return false; // empty is ok
        }
        else
        {
            if (!rgc.pull(d8))
                return false; // empty is ok
        }
        if (d8 < 0x80)
        {
            c = d8;
            return true;
        }
        invalidCharacter(d8);
        return false;
    }


    /// Create a registry of decode functions, index by name
    alias bool function(T, ref dchar)  RecodeFunc;

    __gshared RecodeFunc[string] g8Decoders;

    /// initialize built in decoders
    __gshared static this()
    {
        register("ISO-8859-1",&recode_latin1);
        register("UTF-8",&recode_UTF8);
        register("ASCII",&recode_ascii);
        register("WINDOWS-1252",&recode_windows1252);
    }

    /// Add more if required
    void register(string name, RecodeFunc fn)
    {
        string ucase = name.toUpper();
        g8Decoders[ucase] = fn;
    }

    /// simple switch lookup
    RecodeFunc getRecodeFunc(string name)
    {
        string ucase = name.toUpper();
        auto fn = ucase in g8Decoders;
        return (fn is null) ?  null : *fn;
    }
}


/** 16 bit characters may need endian byte swap **/

template RecodeWChar(T)
{

    alias bool function(T, ref dchar)  RecodeFunc;

    /** UTF-16 after byte reversal recoded as UTF-32 **/
    bool recode_swap_utf16(T rgw, ref dchar c)
    {
        wswapchar swp = void;
        wswapchar result = void;
        static if(isDelegate!(T) || isFunctionPointer!(T))
        {
            if (!rgw(swp.w0))
                return false;
        }
        else static if (isPullRange!(T))
        {
            if (!rgw.pull(swp.w0))
                return false;
        }
        result.c.c0 = swp.c.c1;
        result.c.c1 = swp.c.c0;

        if (result.w0 < 0xD800 || result.w0 >= 0xE000)
        {
            c = result.w0;
            return true;
        }

        dchar d = result.w0 & 0x3FF;
        static if(isDelegate!(T) || isFunctionPointer!(T))
        {
            if (!rgw(swp.w0))
                return false;
        }
        else
        {
            if (!rgw.pull(swp.w0))
                return false;
        }
        result.c.c0 = swp.c.c1;
        result.c.c1 = swp.c.c0;

        c = 0x10000 + ((result.w0 & 0x3FF) << 10) + d;
        return true;
    }
    /** UTF-16 in system endian to UTF-32 **/
    bool recode_utf16(T rgw, ref dchar c)
    {
        wchar w16;

        static if(isDelegate!(T) || isFunctionPointer!(T))
        {
            if (!rgw(w16))
                return false;
        }
        else static if (isPullRange!(T))
        {
            if (!rgw.pull(w16))
                return false;
        }

        dchar result = w16;
        if (result < 0xD800 || result >= 0xE000)
        {
            c = result;
            return true;
        }

        static if(isDelegate!(T) || isFunctionPointer!(T))
        {
            if (!rgw(w16))
                return false;
        }
        else static if (isPullRange!(T))
        {
            if (!rgw.pull(w16))
                return false;
        }

        c = 0x10000 + ((result&0x3FF) << 10) + ( w16 & 0x3FF);
        return true;
    }

    /// select recode function based on name.
    RecodeFunc getRecodeFunc(string name)
    {
        string upcase = name.toUpper();
        switch(name)
        {
        case "UTF-16LE":
            if (endian == Endian.bigEndian)
                return &recode_swap_utf16;
            else
                return &recode_utf16;

        case "UTF-16BE":
            if (endian == Endian.bigEndian)
                return &recode_utf16;
            else
                return &recode_swap_utf16;

        case "UTF-16":
            return &recode_utf16;

        default:
            return null;
        }
    }
}

/// append a dchar to UTF-8 string

void appendUTF8(ref char[] s, dchar d)
{
    if (d < 0x80)
    {
        // encode in 7 bits, 1 byte
        s ~= cast(char) d;
        return;
    }
    else
    {
        if (d < 0x800)
        {
            // encode in 11 bits, 2 bytes
            char c2 = d & 0xBF;
            d >>= 6;
            s ~= cast(char) (d | 0xC0);
            s ~= c2;
            return;
        }
        else if (d < 0x10000)
        {
            // encode in 16 bits, 3 bytes
            char c3 = cast(char) (d & 0xBF);
            d >>= 6;
            char c2 = cast(char) (d & 0xBF);
            d >>= 6;
            s ~= cast(char) (d | 0xE0);
            s ~= c2;
            s ~= c3;
            return;
        }
        else if (d > 0x10FFFF)
        {
            // not in current unicode range?
            throw new RangeError("Unicode character greater than x10FFFF",__LINE__);
        }
        else
        {
            // encode in 21 bits, 4 bytes
            char c4 = cast(char) (d & 0xBF);
            d >>= 6;
            char c3 = cast(char) (d & 0xBF);
            d >>= 6;
            char c2 = cast(char) (d & 0xBF);
            d >>= 6;
            s ~= cast(char) (d | 0xF0);
            s ~= c2;
            s ~= c3;
            s ~= c4;
            return;
        }
    }
}


/// UTF-32 reader which is a straight read.
template RecodeDChar(T)
{
    alias bool function(T, ref dchar)  RecodeFunc;

    bool read_utf32(T rgd, ref dchar c)
    {
        static if(isDelegate!(T) || isFunctionPointer!(T))
        {
            if (!rgd(c))
                return false;
        }
        else static if (isPullRange!(T))
        {
            if (!rgd.pull(c))
                return false;
        }
        return true;
    }

    RecodeFunc getRecodeFunc(string name)
    {
        string upcase = name.toUpper();
        switch(name)
        {	
        case "UTF-32":
        case "UTF-32BE":
        case "UTF-32LE":
            return &read_utf32; //TODO: this must be wrong for some.
        default:
            return null;
        }
    }
}

/// DecoderKey is a UTF code name, and BOM name pairing.

struct DecoderKey
{
    string codeName;
    string bomName;

    this(string encode,string bom = null)
{
    codeName = encode;
    bomName = bom;
}
/// key supports a hash
const hash_t toHash() nothrow @safe
{
    hash_t result;
    foreach(c ; codeName)
    result = result * 11 + c;

    if (bomName !is null)
        foreach(c ; bomName)
        result = result * 11 + c;
    return result;
}

/// key as a string
const  string toString()
{
    return text(codeName,bomName);
}

/// key supports compare
const int opCmp(ref const DecoderKey s)
{
    int result = cmp(this.codeName, s.codeName);
    if (!result)
    {
        if (this.bomName is null)
        {
            result = (s.bomName is null) ? 0 : -1;
        }
        else
        {
            result =  (s.bomName !is null) ? cmp(this.bomName, s.bomName) : 1;
        }
    }
    return result;
}
}


/** Associate the DecoderKey with its bom byte sequence,
 *  an endian value, and bits per character
 **/

class ByteOrderMark
{
    DecoderKey	key;
    ubyte[]		bom;
    Endian		endOrder;
    uint		charSize;

    this(DecoderKey k, ubyte[] marks, Endian ed, uint bsize)
{
    key = k;
    bom = marks;
    endOrder = ed;
    charSize = bsize;
}
};

/**
 * BOM and encoding registry initialisation
 **/

struct ByteOrderRegistry
{
    __gshared ByteOrderMark[]	list;

    /// Used for no match found
    __gshared ByteOrderMark	noMark;

    __gshared static this()
{
    noMark = new ByteOrderMark(DecoderKey("UTF-8",null), [], endian, 1);
    register(new ByteOrderMark(DecoderKey("UTF-8",null), [0xEF, 0xBB, 0xBF], endian, 1));
    register(new ByteOrderMark(DecoderKey("UTF-16","LE"), [0xFF, 0xFE], Endian.littleEndian, 2));
    register(new ByteOrderMark(DecoderKey("UTF-16","BE"), [0xFE, 0xFF], Endian.bigEndian, 2));
    register(new ByteOrderMark(DecoderKey("UTF-32","LE"), [0xFF, 0xFE, 0x00, 0x00], Endian.littleEndian, 4));
    register(new ByteOrderMark(DecoderKey("UTF-32","BE"), [0x00, 0x00, 0xFE, 0xFF], Endian.bigEndian,4));
}

/// add  ByteOrderMark signatures
static void register(ByteOrderMark bome)
{
    list ~= bome;
}

}


/**
 * Read beginning of a block stream, and return what appears to
 * be a valid ByteOrderMark class describing the characteristics of any
 * BOM found.   If there is no BOM, the instance ByteOrderRegistry.noMark will
 * be returned, describing a UTF8 stream, system endian, with empty BOM array,
 * and character size of 1.
 *
 * The buffer array will hold all values in stream sequence, that were read by the
 * function after reading the BOM. If no BOM was recognized the buffer array contains
 * all the values currently read from the stream. The number of bytes in buffer
 * will be a multiple of the number of bytes in the detected character size of the stream
 * (ByteOrderMark.charSize). If end of stream is encountered or an exception occurred
 * the eosFlag will be true.
 *
 */
ByteOrderMark readStreamBOM(Stream s, ref Array!ubyte result, out bool eosFlag)
{
    ubyte test;
	Array!ubyte bomchars;


    ByteOrderMark[] goodList = ByteOrderRegistry.list.dup;
    ByteOrderMark[] fullMatch;

    auto goodListCount = goodList.length;
    ByteOrderMark found = null;
    try
    {
        eosFlag = false;
        int  readct = 0;
        while (goodListCount > 0)
        {
            s.read(test);
            readct++;
            bomchars ~= test;
            foreach(gx , bm ; goodList)
            {
                if (bm !is null)
                {
                    auto marklen = bm.bom.length;
                    if (readct <= marklen)
                    {
                        if (test != bm.bom[readct-1])
                        {
                            // eliminate from array
                            goodList[gx] = null;
                            goodListCount--;
                        }
                        else if (readct == marklen)
                        {
                            fullMatch ~= bm;
                            goodList[gx] = null;
                            goodListCount--;
                        }
                    }
                }
            }
        }
        if (fullMatch.length > 0)
        {
            // any marks fully matched ?
            found = fullMatch[0];
            for(size_t fz = 1; fz < fullMatch.length; fz++)
            {
                if (found.bom.length < fullMatch[fz].bom.length)
                    found = fullMatch[fz];
            }
        }
        else
        {
            found = ByteOrderRegistry.noMark;
        }

        // need to read to next full charSize to have at least 1 valid character
        //bool validChar = true;
        while ((bomchars.length - found.bom.length) % found.charSize != 0)
        {
            s.read(test);
            bomchars ~= test;
        }
        // if (validChar)
        result = bomchars.slice(found.bom.length, bomchars.length);
        return found;
    }
    catch(Exception re)
    {
        if (bomchars.length == 0)
        {
            result.length = 0;
            eosFlag = true;
            return ByteOrderRegistry.noMark;
        }
    }

    result = bomchars;
    return ByteOrderRegistry.noMark;
}


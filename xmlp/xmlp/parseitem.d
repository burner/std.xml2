/**

Authors: Michael Rynn
Licence: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Distributed under the Boost Software License, Version 1.0.

Shared data definitions for communicating with the parser.

*/

module xmlp.xmlp.parseitem;

import xmlp.xmlp.xmlchar;
import std.string;
import std.stdint;
import core.memory;

import alt.zstring;

static if (__VERSION__ <= 2053)
{
    import std.ctype;
    alias std.ctype.isdigit isDigit;
}
else
{
    import std.ascii;
}

private import std.c.string :
memcpy;

/// Rationalize the error messages here.  More messages and functionality to add.

/// Standard DOM node type identification
enum NodeType
{
    None = 0,
    Element_node = 1,
    Attribute_node =2,
    Text_node =3,
    CDATA_Section_node =4,
    Entity_Reference_node =5,
    Entity_node =6,
    Processing_Instruction_node =7,
    Comment_node =8,
    Document_node =9,
    Document_type_node =10,
    Document_fragment_node =11,
    Notation_node = 12
};

version (CustomAA)
{
	import alt.arraymap;
	alias HashTable!(string,string) StringMap;
	alias HashTable!(dchar, string) ReverseEntityMap;
}
else {
alias string[string] StringMap;
alias string[dchar] ReverseEntityMap;
}


unittest
{
    AttributeMap amap;

    amap["tname"]="tval";
    assert(amap.length==1);
}
/**
	Returns parsed fragment of XML. The type indicates what to expect.
*/

enum XmlResult
{
    TAG_START, /// Element name in scratch.  Attributes in names and values. Element content expected next.
    TAG_SINGLE, /// Element name in scratch.  Attributes in names and values. Element has no content.
	TAG_EMPTY = TAG_SINGLE,
    TAG_END,   /// Element end tag.  No more element content.
    STR_TEXT,  /// Text block content.
    STR_CDATA, /// CDATA block content.
    STR_PI,		///  Processing Instruction.  Name in names[0].  Instruction content in values[0].
    STR_COMMENT,  /// Comment block content.
	XML_DEC,   /// XML declaration.  Declaration attributes in names and values.
    DOC_END,      /// Parse finished
	DOC_TYPE,	/// DTD parse results contained in doctype as DtdValidate.
	XI_NOTATION,
	XI_ENTITY,
	XI_OTHER,		/// internal DOCTYPE declarations
	RET_NULL,  /// nothing returned
	ENUM_LENGTH, /// size of array to hold all the other values
};





	alias KeyValueBlock!(string,string,true) AttributeMap;
	alias AttributeMap AttributePairs;

	/// As collection key
	struct XmlKey
	{
		const(char)[]       path_;
		XmlResult           type_;

		const hash_t toHash() nothrow @safe
		{
			hash_t result = type_;
			foreach(char c ; path_)
				result = result * 13 + c;
			return result;
		}

		const int opCmp(ref const XmlKey S)
		{
			int diff = S.type_ - this.type_;
			if (diff == 0)
				diff = cmp(S.path_, this.path_);
			return diff;
		}
	}
	/**

	Using an Associative Array to store attributes as name - value pairs,
	although it would seem a natural thing to do, was a performance drag,
	on most of large and small xml files tried so far. Even with a file with a dozen
	attributes on each element (unicode database file). 
	Maybe the break even point for the number of attributes for
	AA vs linear array seems too high.

	*/
	struct XmlReturn
	{
		XmlResult		type = XmlResult.RET_NULL;
		string			scratch;
		AttributeMap	attr;
		Object			node; // maybe used to pass back some xml node or object
		
		/// should use attr[val].
		deprecated string opIndex(string val) 
		{
			return attr.opIndex(val);
		}
		void clear()
		{
			scratch = null;
			node = null;
			attr.clear();
			type = XmlResult.RET_NULL;
		}
	}


	alias void delegate(ref XmlReturn ret) ParseDg;


/// number class returned by parseNumber
enum NumberClass
{
    NUM_ERROR = -1,
    NUM_EMPTY,
    NUM_INTEGER,
    NUM_REAL
};

/**
Parse regular decimal number strings.
Returns -1 if error, 0 if empty, 1 if integer, 2 if floating point.
 and the collected string.
No NAN or INF, only error, empty, integer, or real.
process a string, likely to be an integer or a real, or error / empty.
*/

NumberClass
parseNumber(R,W)(R rd, auto ref W wr,  int recurse = 0 )
{
    int   digitct = 0;
    bool  done = rd.empty;
    bool  decPoint = false;
    for(;;)
    {
        if (done)
            break;
        auto test = rd.front;
        switch(test)
        {
        case '-':
        case '+':
            if (digitct > 0)
            {
                done = true;
            }
            break;
        case '.':
            if (!decPoint)
                decPoint = true;
            else
                done = true;
            break;
        default:
            if (!std.ascii.isDigit(test))
            {
                done = true;
                if (test == 'e' || test == 'E')
                {
                    // Ambiguous end of number, or exponent?
                    if (recurse == 0)
                    {
                        wr.put(cast(char)test);
                        rd.popFront();
                        if (parseNumber(rd,wr, recurse+1)==NumberClass.NUM_INTEGER)
                            return NumberClass.NUM_REAL;
                        else
                            return NumberClass.NUM_ERROR;
                    }
                    // assume end of number
                }
            }
            else
                digitct++;
            break;
        }
        if (done)
            break;
        wr.put(cast(char)test);
        rd.popFront();
        done = rd.empty;
    }
    if (decPoint)
        return NumberClass.NUM_REAL;
    if (digitct == 0)
        return NumberClass.NUM_EMPTY;
    return NumberClass.NUM_INTEGER;
};

/// read in a string till encounter a character in sepChar set
bool readToken(R,W) (R rd, dstring sepSet, auto ref W wr)
{
    bool hit = false;
SCAN_LOOP:
    for(;;)
    {
        if (rd.empty)
            break;
        auto test = rd.front;
        foreach(dchar sep ; sepSet)
        if (test == sep)
            break SCAN_LOOP;
        wr.put(test);
        rd.popFront();
        hit = true;
    }
    return hit;
}
/// read in a string till encounter the dchar
bool readToken (R,W) (R rd, dchar match, auto ref W wr)
{
    bool hit = false;
SCAN_LOOP:
    for(;;)
    {
        if (rd.empty)
            break;
        auto test = rd.front;
        if (test == match)
            break SCAN_LOOP;
        wr.put(test);
        rd.popFront();
        hit = true;
    }
    return hit;
}

/** eat up exact match and return true. */
bool match(R)(R rd, dstring ds)
{
    auto slen = ds.length;
    if (slen == 0)
        return false; // THROW EXCEPTION ?
    size_t ix = 0;
    while ((ix < slen) && !rd.empty && (rd.front == ds[ix]))
    {
        ix++;
        rd.popFront();
    }
    if (ix==slen)
        return true;
    if (ix > 0)
        rd.pushFront(ds[0..ix]);
    return false;
}

bool matchChar(R)(R rd, dchar c)
{
    if (rd.empty)
        return false;
    if (c == rd.front)
    {
        rd.popFront();
        return true;
    }
    return false;
}


uint countSpace(R)(R rd)
{
    uint   count = 0;
    while(!rd.empty)
    {
        switch(rd.front)
        {
        case 0x020:
            break;
        case 0x09:
            break;
        case 0x0A:
            break;
        case 0x0D:
            break;
        default:
            return count;
        }
        rd.popFront();
        count++;
    }
    return count;
}
/** Using xml 1.1 (or 1.0 fifth edition ), plus look for ::, which terminates a name.
	name, or name::, return name, and -1 (need to check src further to disambiguate ::)
	return name:qname, and position of first ':'


*/

bool getQName(R)(R src, ref Array!char scratch, ref intptr_t prefix)
{
    scratch.length = 0;
    if (src.empty || !isNameStartChar11(src.front))
        return false;

    scratch.put(src.front);
    src.popFront();
    intptr_t ppos = -1;
    while(!src.empty)
    {
        dchar test = src.front;
        if (test == ':')
        {
            if (ppos >= 0)
            {
                // already got prefix
                break;
            }
            src.popFront();
            test = src.front;
            if (test == ':')
            {
                // end of name was reached, push back, leaving ::
                src.pushFront(':');
                break;
            }
            // its a prefix:name ?
            ppos = scratch.length;
            scratch.put(':');

        }
        if (isNameChar11(test))
            scratch.put(test);
        else
            break;
        src.popFront();
    }
    prefix = ppos;
    return true;
}

// presume front contains first quote character
bool unquote(R)(R src, ref Array!char scratch )
{
    dchar terminal = src.front;
    src.popFront();
    scratch.length = 0;

    for(;;)
    {
        if (src.empty)
            return false;
        if (src.front != terminal)
            scratch.put(src.front);
        else
        {
            src.popFront();
            break;
        }
        src.popFront();
    }
    return true;
}

bool getAttribute(R)(R src, ref string atname, ref string atvalue)
{
    Array!char temp;
    intptr_t pos;
    countSpace(src);
    if (getQName(src, temp, pos))
    {
        countSpace(src);
        if (match(src,"="))
        {
            countSpace(src);
            dchar test = src.front;
            atname = temp.unique;
            if (test=='\"' || test == '\'')
            {
                if (unquote(src, temp))
                {
                    atvalue = temp.unique;
                    return true;
                }
            }
        }
    }
    return false;
}

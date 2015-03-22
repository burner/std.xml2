/**
	Part of xmlp.xmlp package reimplementation of std.xml (cf.)
    XML Character classifcation functions, adapted mostly the same as original std.xml.

Authors: Janice Canon, Michael Rynn
Licence: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)

*/

module xmlp.xmlp.xmlchar;
import std.string;
import std.stdint;
/**
 * XML 1.1 allows nearly all control characters to be in the document as character entities,
 * but they are disallowed in the raw source ( except for #9, #10, #13, #85 ).
 * Raw #13 and #85 are also filtered out by end of line handling.
 *
 **/

bool isControlCharRef11(dchar c)
{
    if (c <= 0x1F)
    {
        switch(c)
        {
        case 0x09:
        case 0x0A:
        case 0x0:
        case 0x0D:
            return false;
        default:
            return true;
        }
    }
    if (c <= 0x9F)
    {
        return (c >= 0x7F) && (c != 0x85);
    }
    return false;
}

/**

*/

/**
 * The character fits the broad definition of
 * a XML document source character for XML 1.0.
 #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]

 */

pure bool isChar10(dchar c)
{
    return
        ((c >= 0x20) && (c <= 0xD7FF)) ? true
        : (c < 0x20) ? (c==0xA)||(c==0x9)||(c==0xD)
        : ((c >= 0xE000) && (c <= 0xFFFD)) || ((c >= 0x10000) && (c <= 0x10FFFF));
}

alias isChar10	isChar;

/**
 * The character fits the broad definition of
 * a XML document source character for XML 1.1.
 [#x1-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]
 and is not a member of a restricted set of characters which must
 not be directly embedded in the source.
[#x1-#x8] | [#xB-#xC] | [#xE-#x1F] | [#x7F-#x84] | [#x86-#x9F]

 */
pure bool isChar11(dchar c)
{
    return
        ((c >= 0x20) && (c < 0x7F)) ? true
        : (c < 0x20) ? (c==0xA)||(c==0x9)||(c==0xD)
        : (c <= 0xD7FF) ? (c > 0x9F) || (c == 0x85)
        : ((c >= 0xE000) && (c <= 0xFFFD)) || ((c >= 0x10000) && (c <= 0x10FFFF));
}


/// characters allowed by isChar10, but 'discouraged' by XML 1.0
///
pure bool isDiscouragedChar(dchar c)
{
    if (c <= 0x9F)
    {
        return ((c >= 0x7F) && (c != 0x85));
    }
    if (c <= 0xFDEF)
    {
        return ( c >= 0xFDD0);
    }
    if (c >= 0x1FFFE)
    {
        return ((c & 0xFFFE) == 0xFFFE);
    }
    return false;
}

unittest
{
//  const CharTable=[0x9,0x9,0xA,0xA,0xD,0xD,0x20,0xD7FF,0xE000,0xFFFD,
//        0x10000,0x10FFFF];

    immutable dstring goodChar10 = [
        '\x09' ,0xA,0xD,0x20,'J',
        0xD7FF,0xE000,0xFFFD,0x10000,0x10FFFF
    ];
    immutable dstring badChar10 = [
        0x08,0xB,0xC,0xE,0x1F,0xD800,0xDFFF,0xFFFE,0xFFFF
    ];

    foreach(d ; goodChar10)
    assert(isChar10(d));
    foreach(d ; badChar10)
    assert(!isChar10(d));

    assert(!isChar10(cast(dchar)0x110000));

    immutable dstring goodChar11 = [
        0x85, 0x2028
    ];

    foreach(d ; goodChar11)
    assert(isChar11(d));
}

/**
 * Returns true if the character is whitespace according to the XML standard
 *
 * Only the following characters are considered whitespace in XML - space, tab,
 * carriage return and linefeed
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 *
 * Params:
 *    c = the character to be tested
 */
pure bool isSpace(dchar c)
{
    switch(c)
    {
    case '\u0020':
    case '\u0009':
    case '\u000A':
    case '\u000D':
        return true;
    default:
        return false;
    }
}

/**
 * Part of PUBLIC identifier
 **/
pure bool isPublicChar(dchar test)
{
    /// Allowed are #x20 | #xD | #xA | [a-zA-Z0-9] | [-'()+,./:=?;!*#@$_%]

    if (test >= '\u0020' && test <= 'Z')
    {
        // exclude double quote,ampersand, less and greater than
        switch(test)
        {
        case '\u0022': // quote
        case '\u0026': // ampersand
        case '\u003C': // <
        case '\u003E': // >
            return false;
        default:
            return true;
        }
    }
    if (test >= 'a' && test <= 'z')
        return true;
    switch(test)
    {
    case  '\u005F': // underscore
    case  '\u000A':
    case  '\u000D':
        return true;
    default:
        return false;
    }
}


private
{
    /**
     * Up to and including fourth edition names start with Letter | '_' | ':'
     * Errata E09 changed this.
     **/
    immutable dstring NameStartCharTable=[
        ':',':',  'A','Z',  '_','_',  'a', 'z',
        0xC0,0xD6,	0xD8,0xF6, 0xF8,0x2FF,
        0x370,0x37D, 0x37F,0x1FFF, 0x200C,0x200D,
        0x2070,0x218F, 0x2C00,0x2FEF, 0x3001,0xD7FF,
        0xF900,0xFDCF, 0xFDF0, 0xFFFD, 0x10000,0xEFFFF
    ];

    /// adds | "-" | "." | [0-9] | #xB7 | [#x0300-#x036F] | [#x203F-#x2040]
    immutable dstring NameCharTable=[
        '-','.',  '0','9', //add
        ':',':',  'A','Z',  '_','_',  'a', 'z',
        0xB7,0xB7,  //add
        0xC0,0xD6,	0xD8,0xF6, 0xF8,0x2FF,
        0x0300,0x036F, //add
        0x370,0x37D, 0x37F,0x1FFF, 0x200C,0x200D,
        0x203F,0x2040, //add
        0x2070,0x218F, 0x2C00,0x2FEF, 0x3001,0xD7FF,
        0xF900,0xFDCF, 0xFDF0, 0xFFFD, 0x10000,0xEFFFF
    ];



}


pure bool isNameStartChar10(dchar c)
{
    if (
        ((c >= 'a') && (c <= 'z')) ||
        ((c >= 'A') && (c <= 'Z')) ||
        c == ':' || c == '_'
    )
        return true;
    else
        return isLetter(c);

}
/**
 * Up to and including fourth edition there was no name start character restriction,
 * and  Letter | Digit | '.' | '-' | '_' | ':' | CombiningChar | Extender was OK for all name characters
 * Errata E09 changed this, so that isNameStartChar11 is appropriate for the Fifth Edition 1.0
 **/

pure bool isNameChar10(dchar c)
{
    if (
        ((c >= 'a') && (c <= 'z')) ||
        ((c >= 'A') && (c <= 'Z')) ||
        ((c >= '0') && (c <= '9')) ||
        c == '-' || c == '.' || c == ':' || c == '_'
    )
        return true;
    else
        return isLetter(c) || isDigit(c) || isCombiningChar(c) || isExtender(c);

}

/**
 * Starts an Xml name,from since the fifth edition of XML 1.0 recommendations (Feb 2008).
 * ":" | [A-Z] | "_" | [a-z] | [#xC0-#xD6] | [#xD8-#xF6] | [#xF8-#x2FF] | [#x370-#x37D] | [#x37F-#x1FFF]
 * | [#x200C-#x200D] | [#x2070-#x218F] | [#x2C00-#x2FEF] | [#x3001-#xD7FF] | [#xF900-#xFDCF] | [#xFDF0-#xFFFD]
 * Lookup is ASCII biased.
 *
 *
  **/
pure bool isNameStartChar11(dchar c)
{
    if (
        ((c >= 'a') && (c <= 'z')) ||
        ((c >= 'A') && (c <= 'Z')) ||
        c == ':' || c == '_'
    )
        return true;
    else
    {
        return lookup(NameStartCharTable,c);
    }
}
/**
 * Character is part of XmlName or NmToken
 * isNameStart | "-" | "." | [0-9] | #xB7 | [#x0300-#x036F] | [#x203F-#x2040]
 * ASCII biased lookup.
 **/

pure bool isNameChar11(dchar c)
{
    if (
        ((c >= 'a') && (c <= 'z')) ||
        ((c >= 'A') && (c <= 'Z')) ||
        ((c >= '0') && (c <= '9')) ||
        c == '-' || c == '.' || c == ':' || c == '_'
    )
        return true;
    else
        return lookup(NameCharTable,c);
}

/**
 * Control character range - space
 *
 **/
pure bool isControl(dchar c)
{
    if (c < '\u0020')
    {
        switch(c)
        {
        case '\u0009':
        case '\u000A':
        case '\u000D':
            return false;
        default:
            return true;
        }
    }
    return false;
}
/**
 * Returns true if the character is a digit according to the XML standard
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 *
 * Params:
 *    c = the character to be tested
 */
pure bool isDigit(dchar c)
{
    if (c <= 0x0039 && c >= 0x0030)
        return true;

    return lookup(DigitTable,c);
}

/**
 * Returns true if the character is a letter according to the XML standard
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 *
 * Params:
 *    c = the character to be tested
 */
pure bool isLetter(dchar c) // rule 84
{
    return isIdeographic(c) || isBaseChar(c);
}

/**
 * Returns true if the character is an ideographic character according to the
 * XML standard
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 *
 * Params:
 *    c = the character to be tested
 */


pure bool isIdeographic(dchar c)
{
    if (c < 0x3007 || c > 0x9FA5)
        return false;
    if ((c >= 0x4E00) || (c == 0x3007) || (c >= 0x3021 && c <= 0x3029))
        return true;
    return false;
}

/**
 * Returns true if the character is a base character according to the XML
 * standard
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 *
 * Params:
 *    c = the character to be tested
 * This version is biased for detecting ASCII characters in the
 * first five character ranges 0x0041 - 0x005A, 0x0061- 0x007A,
 * 0x00C0 - 0x00D6, 0x00D8 - 0x00F6, 0x00F8 - 0x00FF,
 */
pure bool isBaseChar(dchar c)
{
    if (c < 0x100)
    {
        if (c <= 0x007A)
        {
            return (c >= 0x0061) || ((c >= 0x0041) && (c <= 0x005A));
        }

        if (c >= 0x00C0)
        {
            return (c <= 0x00D6) || ((c >= 0x00D8) && (c <= 0x00F6)) || (c >= 0x00F8);
        }
        return false;
    }
    else
        return lookup(BaseCharTable,c);
}

/**
 * Returns true if the character is a combining character according to the
 * XML standard
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 *
 * Params:
 *    c = the character to be tested
 */
pure bool isCombiningChar(dchar c)
{
    return lookup(CombiningCharTable,c);
}

/**
 * Returns true if the character is an extender according to the XML standard
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 *
 * Params:
 *    c = the character to be tested
 */
pure bool isExtender(dchar c)
{
    return lookup(ExtenderTable,c);
}

/// Return encoded source string using a character to entity map
dstring
entityEncode(in dstring s, in dstring[dchar] eArray)
{
    dchar[] result;
    uintptr_t uncopied = 0;

    foreach(i,c ; s)
    {
        version(D_Version2)
        {
            mixin(`const(dstring)* entity = c in eArray; `);
        }
        else
        {
            dstring* entity = c in eArray;
        }
        if (entity !is null)
        {
            result ~= s[uncopied .. i];
            uncopied = i+1;
            result ~= *entity;
        }
    }
    if (uncopied == 0)
    {
        return s;
    }
    else
    {
        result ~= s[uncopied .. $];
        version(D_Version2)
        {
            return result.idup;
        }
        else
        {
            return result;
        }
    }
}



private
{
    // Definitions from the XML specification
    immutable dstring CharTable=[0x9,0x9,0xA,0xA,0xD,0xD,0x20,0xD7FF,0xE000,0xFFFD,
    0x10000,0x10FFFF];

    immutable dstring BaseCharTable=[0x0041,0x005A,0x0061,0x007A,0x00C0,0x00D6,0x00D8,
    0x00F6,0x00F8,0x00FF,0x0100,0x0131,0x0134,0x013E,0x0141,0x0148,0x014A,
    0x017E,0x0180,0x01C3,0x01CD,0x01F0,0x01F4,0x01F5,0x01FA,0x0217,0x0250,
    0x02A8,0x02BB,0x02C1,0x0386,0x0386,0x0388,0x038A,0x038C,0x038C,0x038E,
    0x03A1,0x03A3,0x03CE,0x03D0,0x03D6,0x03DA,0x03DA,0x03DC,0x03DC,0x03DE,
    0x03DE,0x03E0,0x03E0,0x03E2,0x03F3,0x0401,0x040C,0x040E,0x044F,0x0451,
    0x045C,0x045E,0x0481,0x0490,0x04C4,0x04C7,0x04C8,0x04CB,0x04CC,0x04D0,
    0x04EB,0x04EE,0x04F5,0x04F8,0x04F9,0x0531,0x0556,0x0559,0x0559,0x0561,
    0x0586,0x05D0,0x05EA,0x05F0,0x05F2,0x0621,0x063A,0x0641,0x064A,0x0671,
    0x06B7,0x06BA,0x06BE,0x06C0,0x06CE,0x06D0,0x06D3,0x06D5,0x06D5,0x06E5,
    0x06E6,0x0905,0x0939,0x093D,0x093D,0x0958,0x0961,0x0985,0x098C,0x098F,
    0x0990,0x0993,0x09A8,0x09AA,0x09B0,0x09B2,0x09B2,0x09B6,0x09B9,0x09DC,
    0x09DD,0x09DF,0x09E1,0x09F0,0x09F1,0x0A05,0x0A0A,0x0A0F,0x0A10,0x0A13,
    0x0A28,0x0A2A,0x0A30,0x0A32,0x0A33,0x0A35,0x0A36,0x0A38,0x0A39,0x0A59,
    0x0A5C,0x0A5E,0x0A5E,0x0A72,0x0A74,0x0A85,0x0A8B,0x0A8D,0x0A8D,0x0A8F,
    0x0A91,0x0A93,0x0AA8,0x0AAA,0x0AB0,0x0AB2,0x0AB3,0x0AB5,0x0AB9,0x0ABD,
    0x0ABD,0x0AE0,0x0AE0,0x0B05,0x0B0C,0x0B0F,0x0B10,0x0B13,0x0B28,0x0B2A,
    0x0B30,0x0B32,0x0B33,0x0B36,0x0B39,0x0B3D,0x0B3D,0x0B5C,0x0B5D,0x0B5F,
    0x0B61,0x0B85,0x0B8A,0x0B8E,0x0B90,0x0B92,0x0B95,0x0B99,0x0B9A,0x0B9C,
    0x0B9C,0x0B9E,0x0B9F,0x0BA3,0x0BA4,0x0BA8,0x0BAA,0x0BAE,0x0BB5,0x0BB7,
    0x0BB9,0x0C05,0x0C0C,0x0C0E,0x0C10,0x0C12,0x0C28,0x0C2A,0x0C33,0x0C35,
    0x0C39,0x0C60,0x0C61,0x0C85,0x0C8C,0x0C8E,0x0C90,0x0C92,0x0CA8,0x0CAA,
    0x0CB3,0x0CB5,0x0CB9,0x0CDE,0x0CDE,0x0CE0,0x0CE1,0x0D05,0x0D0C,0x0D0E,
    0x0D10,0x0D12,0x0D28,0x0D2A,0x0D39,0x0D60,0x0D61,0x0E01,0x0E2E,0x0E30,
    0x0E30,0x0E32,0x0E33,0x0E40,0x0E45,0x0E81,0x0E82,0x0E84,0x0E84,0x0E87,
    0x0E88,0x0E8A,0x0E8A,0x0E8D,0x0E8D,0x0E94,0x0E97,0x0E99,0x0E9F,0x0EA1,
    0x0EA3,0x0EA5,0x0EA5,0x0EA7,0x0EA7,0x0EAA,0x0EAB,0x0EAD,0x0EAE,0x0EB0,
    0x0EB0,0x0EB2,0x0EB3,0x0EBD,0x0EBD,0x0EC0,0x0EC4,0x0F40,0x0F47,0x0F49,
    0x0F69,0x10A0,0x10C5,0x10D0,0x10F6,0x1100,0x1100,0x1102,0x1103,0x1105,
    0x1107,0x1109,0x1109,0x110B,0x110C,0x110E,0x1112,0x113C,0x113C,0x113E,
    0x113E,0x1140,0x1140,0x114C,0x114C,0x114E,0x114E,0x1150,0x1150,0x1154,
    0x1155,0x1159,0x1159,0x115F,0x1161,0x1163,0x1163,0x1165,0x1165,0x1167,
    0x1167,0x1169,0x1169,0x116D,0x116E,0x1172,0x1173,0x1175,0x1175,0x119E,
    0x119E,0x11A8,0x11A8,0x11AB,0x11AB,0x11AE,0x11AF,0x11B7,0x11B8,0x11BA,
    0x11BA,0x11BC,0x11C2,0x11EB,0x11EB,0x11F0,0x11F0,0x11F9,0x11F9,0x1E00,
    0x1E9B,0x1EA0,0x1EF9,0x1F00,0x1F15,0x1F18,0x1F1D,0x1F20,0x1F45,0x1F48,
    0x1F4D,0x1F50,0x1F57,0x1F59,0x1F59,0x1F5B,0x1F5B,0x1F5D,0x1F5D,0x1F5F,
    0x1F7D,0x1F80,0x1FB4,0x1FB6,0x1FBC,0x1FBE,0x1FBE,0x1FC2,0x1FC4,0x1FC6,
    0x1FCC,0x1FD0,0x1FD3,0x1FD6,0x1FDB,0x1FE0,0x1FEC,0x1FF2,0x1FF4,0x1FF6,
    0x1FFC,0x2126,0x2126,0x212A,0x212B,0x212E,0x212E,0x2180,0x2182,0x3041,
    0x3094,0x30A1,0x30FA,0x3105,0x312C,0xAC00,0xD7A3];

    immutable dstring IdeographicTable=[0x3007,0x3007,0x3021,0x3029,0x4E00,0x9FA5];

    immutable dstring CombiningCharTable=[0x0300,0x0345,0x0360,0x0361,0x0483,0x0486,
    0x0591,0x05A1,0x05A3,0x05B9,0x05BB,0x05BD,0x05BF,0x05BF,0x05C1,0x05C2,
    0x05C4,0x05C4,0x064B,0x0652,0x0670,0x0670,0x06D6,0x06DC,0x06DD,0x06DF,
    0x06E0,0x06E4,0x06E7,0x06E8,0x06EA,0x06ED,0x0901,0x0903,0x093C,0x093C,
    0x093E,0x094C,0x094D,0x094D,0x0951,0x0954,0x0962,0x0963,0x0981,0x0983,
    0x09BC,0x09BC,0x09BE,0x09BE,0x09BF,0x09BF,0x09C0,0x09C4,0x09C7,0x09C8,
    0x09CB,0x09CD,0x09D7,0x09D7,0x09E2,0x09E3,0x0A02,0x0A02,0x0A3C,0x0A3C,
    0x0A3E,0x0A3E,0x0A3F,0x0A3F,0x0A40,0x0A42,0x0A47,0x0A48,0x0A4B,0x0A4D,
    0x0A70,0x0A71,0x0A81,0x0A83,0x0ABC,0x0ABC,0x0ABE,0x0AC5,0x0AC7,0x0AC9,
    0x0ACB,0x0ACD,0x0B01,0x0B03,0x0B3C,0x0B3C,0x0B3E,0x0B43,0x0B47,0x0B48,
    0x0B4B,0x0B4D,0x0B56,0x0B57,0x0B82,0x0B83,0x0BBE,0x0BC2,0x0BC6,0x0BC8,
    0x0BCA,0x0BCD,0x0BD7,0x0BD7,0x0C01,0x0C03,0x0C3E,0x0C44,0x0C46,0x0C48,
    0x0C4A,0x0C4D,0x0C55,0x0C56,0x0C82,0x0C83,0x0CBE,0x0CC4,0x0CC6,0x0CC8,
    0x0CCA,0x0CCD,0x0CD5,0x0CD6,0x0D02,0x0D03,0x0D3E,0x0D43,0x0D46,0x0D48,
    0x0D4A,0x0D4D,0x0D57,0x0D57,0x0E31,0x0E31,0x0E34,0x0E3A,0x0E47,0x0E4E,
    0x0EB1,0x0EB1,0x0EB4,0x0EB9,0x0EBB,0x0EBC,0x0EC8,0x0ECD,0x0F18,0x0F19,
    0x0F35,0x0F35,0x0F37,0x0F37,0x0F39,0x0F39,0x0F3E,0x0F3E,0x0F3F,0x0F3F,
    0x0F71,0x0F84,0x0F86,0x0F8B,0x0F90,0x0F95,0x0F97,0x0F97,0x0F99,0x0FAD,
    0x0FB1,0x0FB7,0x0FB9,0x0FB9,0x20D0,0x20DC,0x20E1,0x20E1,0x302A,0x302F,
    0x3099,0x3099,0x309A,0x309A];

    immutable dstring DigitTable=[0x0030,0x0039,0x0660,0x0669,0x06F0,0x06F9,0x0966,
    0x096F,0x09E6,0x09EF,0x0A66,0x0A6F,0x0AE6,0x0AEF,0x0B66,0x0B6F,0x0BE7,
    0x0BEF,0x0C66,0x0C6F,0x0CE6,0x0CEF,0x0D66,0x0D6F,0x0E50,0x0E59,0x0ED0,
    0x0ED9,0x0F20,0x0F29];

    immutable dstring ExtenderTable=[0x00B7,0x00B7,0x02D0,0x02D0,0x02D1,0x02D1,0x0387,
    0x0387,0x0640,0x0640,0x0E46,0x0E46,0x0EC6,0x0EC6,0x3005,0x3005,0x3031,
    0x3035,0x309D,0x309E,0x30FC,0x30FE];



    pure bool lookup(const(dchar)[] table, dchar c)
    {
        uintptr_t abeg = 0;
        uintptr_t zend = table.length;
        while (abeg < zend)
        {
            immutable m = abeg + ((zend - abeg)/ 2) & ~1; // round down to even number
            if (c < table[m])
            {
                zend = m;
            }
            else if (c > table[m+1])
            {
                abeg = m+2;
            }
            else
            {
                return true;
            }
        }
        return false;
    }

}
/// character matches pattern "a-zA-Z"

pure bool isAlphabetChar(dchar c)
{
    if (c >= 'a' && c <= 'z')
        return true;
    if (c >= 'A' && c <= 'Z')
        return true;
    return false;
}
/// each character matches pattern "a-zA-Z0-9_.-"

pure bool isAsciiName(T : T[])(const(T)[] s1)
{
    foreach(d ; s1)
    {
        if (d >= 'a' && d <= 'z')
            continue;
        if (d >= 'A' && d <= 'Z')
            continue;
        if (d >= '0' && d <= '9')
            continue;
        switch(d)
        {
        case '_':
        case '.':
        case '-':
            break;
        default:
            return false;
        }

    }
    return true;
}

pure bool isDecimalDigits(const(dchar)[] s1)
{
    foreach(d ; s1)
    {
        if (d < '0' || d > '9')
            return false;
    }
    return true;
}
/*
bool eachInPattern(in dstring s1, in string s2)
{
    // all of s1 are in pattern s2
    foreach(d ; s1)
    {
        if (!inPattern(d,s2))
            return false;
    }
    return true;
}
*/

dchar[] trim(dchar[] s)
{
    intptr_t fnsp = -1;
    intptr_t lnsp = -1;
    foreach(ix,d ; s)
    {
        if (!isSpace(d))
        {
            fnsp = ix;
            break;
        }
    }
    if (fnsp < 0)
        return s;

    foreach_reverse(ix,d ; s)
    {
        if (!isSpace(d))
        {
            lnsp = ix+1;
            break;
        }
    }

    return s[fnsp .. lnsp];
}


unittest
{
	alias isChar10 isChar;

	//  const CharTable=[0x9,0x9,0xA,0xA,0xD,0xD,0x20,0xD7FF,0xE000,0xFFFD,
	//        0x10000,0x10FFFF];
    assert(!isChar(cast(dchar)0x8));
    assert( isChar(cast(dchar)0x9));
    assert( isChar(cast(dchar)0xA));
    assert(!isChar(cast(dchar)0xB));
    assert(!isChar(cast(dchar)0xC));
    assert( isChar(cast(dchar)0xD));
    assert(!isChar(cast(dchar)0xE));
    assert(!isChar(cast(dchar)0x1F));
    assert( isChar(cast(dchar)0x20));
    assert( isChar('J'));
    assert( isChar(cast(dchar)0xD7FF));
    assert(!isChar(cast(dchar)0xD800));
    assert(!isChar(cast(dchar)0xDFFF));
    assert( isChar(cast(dchar)0xE000));
    assert( isChar(cast(dchar)0xFFFD));
    assert(!isChar(cast(dchar)0xFFFE));
    assert(!isChar(cast(dchar)0xFFFF));
    assert( isChar(cast(dchar)0x10000));
    assert( isChar(cast(dchar)0x10FFFF));
    assert(!isChar(cast(dchar)0x110000));

    debug (stdxml_TestHardcodedChecks)
    {
        foreach (c; 0 .. dchar.max + 1)
            assert(isChar(c) == lookup(CharTable, c));
    }
}

unittest
{
    debug (stdxml_TestHardcodedChecks)
    {
        foreach (c; 0 .. dchar.max + 1)
            assert(isDigit(c) == lookup(DigitTable, c));
    }
}

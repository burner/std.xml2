/**


Authors: Michael Rynn
Licence: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Distributed under the Boost Software License, Version 1.0.

Functions to pre-filter a file source, or string source, to a produce a UTF-8 string
usable by XmlStringParser in xmlp.xmlp.sliceparse.

This uses the filter and recoding capabilities, and encoding
recognition ability of XmlParser in xmlp.xmlp.xmlparse.

The extra overhead may mean not much performance difference to
using directly the XmlDtdParser in xmlp.xmlp.doctype, or CoreParser in xmlp.xmlp.xmlparse.

*/
module xmlp.xmlp.slicedoc;

import std.stdint;
import xmlp.xmlp.error;
import xmlp.xmlp.sliceparse;
import xmlp.xmlp.linkdom;
import alt.zstring;
import xmlp.xmlp.parseitem;
import xmlp.xmlp.subparse;
import xmlp.xmlp.charinput;
import xmlp.xmlp.xmlparse;
import xmlp.xmlp.coreprint;

import std.conv;
import std.string;
import std.variant;
import std.stream;

/// convenience creator function
IXMLParser parseSliceXml(Document doc, string s)
{
    return new XmlStringParser(s);
}
//
/**
	Filter XML characters, strip original encoding
*/
string decodeXml(XmlParser ps, double XMLVersion, uintptr_t origSize)
{
    Array!char	docString; // expanding buffer
	void putXmlDec(const(char)[] s)
	{
		docString.put(s); // put the declaration back without encoding
	}
    if (!ps.empty)
    {
        // declaration must be first, if it exists
        if (ps.matchInput("<?xml"d))
        {
            XmlReturn xmldec;
            ps.doXmlDeclaration(xmldec);
            // we swallowed the XML declaration, so re-create it,
            // Leave out encoding.
            // TODO: return what the original source encoding was?
       
			printXmlDeclaration(xmldec.attr, &putXmlDec); 
        }
        // get the character type size, and length to reserve space?
        // only approximate, especially when recoding, but so what.

        docString.reserve(origSize);
		ps.notifyEmpty = null; // break apart from context end handler
        while(!ps.empty)
        {
            docString.put(ps.front);
            ps.popFront();
        }
    }
    return docString.unique;	/// TODO: would idup result in smaller (but copied) buffer?   allocator still uses powers of 2.
}

// Filter a string of XML according to XML source rules.
string decodeXmlString(string content, double XMLVersion=1.0)
{
    auto sf = new SliceFill!(char)(content);

    auto ps = new XmlParser(sf,XMLVersion); // filtering parser.
    ps.pumpStart();

    return decodeXml(ps, XMLVersion, content.length);
}

/** Convert any XML file into a UTF-8 encoded string, and filter XML characters
	Strips out original encoding from xml declaration.
*/

string decodeXmlFile(string path, double XMLVersion=1.0)
{
    auto s = new BufferedFile(path);
    auto sf = new XmlStreamFiller(s);

    ulong savePosition = s.position;
    ulong endPosition = s.seekEnd(0);
    s.position(savePosition);

    auto ps = new XmlParser(sf,XMLVersion); // filtering parser.
    ps.pumpStart();
    uint slen = cast(uint) (endPosition / sf.charBytes);

    return decodeXml(ps, XMLVersion, slen);

}

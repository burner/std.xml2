/**
	This is about making XML dcouments just using text strings.

License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Authors: Michael Rynn

Distributed under the Boost Software License, Version 1.0.

This module sees XML as strings for element names, or string pairs for attributes and values,
so it is somewhat independent of the implementation of a DOM.
It gets used by DOM aware implementations.
Each string is output via the delegate StringPutDg.
**/

module xmlp.xmlp.coreprint;

version=ATTRIBUTE_BLOCK;

import xmlp.xmlp.xmlchar;
import xmlp.xmlp.parseitem;
import std.array;
import std.exception;
import std.conv;
import std.string;
import std.stdint;
import alt.zstring;



alias void delegate(const(char)[] s)	StringPutDg;


//alias string[dchar] CharEntityMap;
version (CustomAA)
{
import alt.arraymap;
alias HashTable!(dchar, string) CharEntityMap;
}
else {
alias string[dchar] CharEntityMap;
}
/* Options to control output */

struct XmlPrintOptions
{

    this(StringPutDg dg)
    {
        putDg = dg;
        indentStep = 2;
        emptyTags = true;
        noComments = false;
        noWhiteSpace = false;
        sortAttributes = true;
        encodeNonASCII = false;
        xversion = 1.0;
    }

    CharEntityMap	charEntities;

    uint	indentStep; // increment for recursion
    bool	emptyTags;  // print empty tag style
    bool	noComments;	// no comment output
    bool	noWhiteSpace; // convert whitespace to character reference
    bool	sortAttributes;
    bool	encodeNonASCII;
    double  xversion;

    StringPutDg		putDg;

    /// delayed entity lookup values
    void configEntities()
    {
        charEntities['<'] = "&lt;";
        charEntities['>'] = "&gt;";
        charEntities['\"'] = "&quot;";
        charEntities['&'] = "&amp;";

        if (noWhiteSpace)
        {
            charEntities[0x0A] = "&#10;";
            charEntities[0x0D] = "&#13;";
            charEntities[0x09] = "&#9;";
        }
        if (xversion > 1.0)
        {
            dchar c;
            for (c = 0x1; c <= 0x1F; c++)
            {
                if (isControlCharRef11(c))
                    charEntities[c] = text("&#",cast(uint)c,";");
            }
            for (c = 0x7F; c <= 0x9F; c++)
            {
                charEntities[c] = text("&#",cast(uint)c,";");
            }
        }
    }

	~this()
	{
		version(CustomAA)
		{
			if (charEntities.length > 0)
				charEntities.clear();
		}
	}
}

/// Wrap CDATA and its end around the content

string makeXmlCDATA(string txt)
{
    return text("<![CDATA[", txt, "]]>");
}

/// Wrap the Xml Processing Instruction

string makeXmlProcessingInstruction(string target, string data)
{
    if (data !is null)
        return text("<?", target, " ", data, "?>");
    else
        return text("<?", target," ?>");
}

/// Wrap the text as XML comment

string makeXmlComment(string txt)
{
    return text("<!--", txt, "-->");
}

/// OutputRange (put). Checks every character to see if needs to be entity encoded.
void encodeCharEntity(P)(auto ref P p, string text, CharEntityMap charEntities)
{
    foreach(dchar d ; text)
    {
        auto ps = d in charEntities;
        if (ps !is null)
            p.put(*ps);
        else
            p.put(d);
    }
}

/// Return character entity encoded version of string
string encodeStdEntity(string text,  CharEntityMap charEntities)
{
    char[] buffer;
    auto app = appender(buffer);
    encodeCharEntity(app, text,charEntities);
    buffer = app.data();
    return assumeUnique(buffer);
}

/// right justified index
string doIndent(string s, uintptr_t indent)
{
    char[] buf;
    auto slen = s.length;
    buf.length = indent + slen;
    size_t i = 0;
    while( i < indent)
        buf[i++] = ' ';
    buf[i..i+slen] = s[0..slen];
    return assumeUnique(buf);
}

/// Recursible XML printer that passes along XMLOutOptions
struct XmlPrinter
{
    uint				    indent;// current indent
    XmlPrintOptions*		options;
    private Array!char	pack; // each indent level with reusable buffer

    // constructor for recursion
    this(ref XmlPrinter tp)
    {
        options = tp.options;
        indent = tp.indent + options.indentStep;
    }
    // append with indent  "...<tag"
    private void appendStartTag(string tag)
    {
        immutable original = pack.length;
        immutable taglen = tag.length;
        pack.length = original + indent + taglen + 1;
        char[] buf = pack.toArray[original..$];
        uintptr_t i = indent;
        if (i > 0)
            buf[0..i] = ' ';
        buf[i++] = '<';
        buf[i .. $] = tag[0 .. $];
    }
    // append with indent
    private void appendEndTag(string tag)
    {
        immutable original = pack.length;
        immutable taglen = tag.length;
        pack.length = original + indent + taglen + 3;
        char[] buf = pack.toArray[original..$];
        buf[0..indent] = ' ';
        uintptr_t i = indent;
        buf[i++] = '<';
        buf[i++] = '/';
        buf[i .. i + taglen] = tag;
        i += taglen;
        buf[i] = '>';
    }


    string encodeEntity(string value)
    {
        return encodeStdEntity(value, options.charEntities);
    }

    // constructor for starting
    this(ref XmlPrintOptions opt, uint currentIndent = 0)
    {
        indent = currentIndent;
        options = &opt;

        if (options.charEntities.length == 0)
        {
            options.configEntities();
        }
    }

	~this()
	{

	}
    // string[string] output as XML. There is no encoding here yet.
    // May have to pre-entity encode the AA values.

    @property bool noComments()
    {
        return options.noComments;
    }
    @property bool emptyTags()
    {
        return options.emptyTags;
    }
    @property bool noWhiteSpace()
    {
        return options.noWhiteSpace;
    }

    private void appendAttributes(AttributePairs attr)
    {
        if (attr.length == 0)
            return;
        void output(ref AttributePairs pmap)
        {
            foreach(k,v ; pmap)
            {
                pack.put(' ');
                pack.put(k);
                pack.put('=');
				// By using \", do not have to encode '\'';
                pack.put('\"');
                encodeCharEntity(pack, v, options.charEntities);
                pack.put('\"');
            }
        }

        if (options.sortAttributes)
        {
            if (!attr.sorted)
				attr.sort();
        }
        output(attr);


    }
	void mapToAttributePairs(AttributeMap map, ref AttributePairs ap)
	{
		foreach(n,v ; map)
		{
			ap.put(AttributePairs.BlockRec(n,v));
		}
	}

    /// Element containing attributes and single text content. Encode content.
    void  putTextElement(string ename, string content)
    {
        pack.length = 0;
        pack.reserve(ename.length * 2 + 5 + content.length);
        appendStartTag(ename);
        pack.put('>');
        encodeCharEntity(pack, content, options.charEntities);
		pack.put("</");
		pack.put(ename);
		pack.put('>');
        options.putDg(pack.toArray);
    }
    /// Element containing no attributes and single text content. Encode content.
    void  putTextElement(string ename, AttributeMap map, string content)
    {
        pack.length = 0;
        pack.reserve(ename.length * 2 + 5 + content.length);
        appendStartTag(ename);
        if (map.length > 0)
		{
			AttributePairs ap;
			mapToAttributePairs(map, ap);
            appendAttributes(ap);
		}
        pack.put('>');
        encodeCharEntity(pack, content, options.charEntities);
		pack.put("</");
		pack.put(ename);
		pack.put('>');
        options.putDg(pack.toArray);
    }
    /// indented start tag without attributes
    void putStartTag(string tag)
    {
        pack.length = 0;
        appendStartTag(tag);
        pack.put('>');
        options.putDg( pack.toArray );
    }
    /// indented start tag with attributes
    void putStartTag(string tag, AttributeMap attr, bool isEmpty)
    {
        pack.length = 0;
        appendStartTag(tag);
        if (attr.length > 0)
		{
			AttributePairs ap;
			mapToAttributePairs(attr,ap);
            appendAttributes(ap);
		}
        if (isEmpty)
        {
            if (options.emptyTags)
                pack.put(" />");
            else
            {
                pack.put("></");
                pack.put(tag);
                pack.put('>');
            }
        }
        else
        {
            pack.put('>');
        }
        options.putDg(pack.toArray);
    }

    /// indented empty tag, no attributes
    void putEmptyTag(string tag)
    {
        pack.length = 0;
        if(!options.emptyTags)
        {
            appendStartTag(tag);
            pack.put("></");
            pack.put(tag);
            pack.put('>');
        }
        else
        {
            appendStartTag(tag);
            pack.put(" />");
        }
        options.putDg(pack.toArray);
    }
    /// indented end tag
    void putEndTag(string tag)
    {
        pack.length = 0;
        appendEndTag(tag);
        options.putDg(pack.toArray);
    }

    void putIndent(const(char)[] s)
    {
        pack.length = indent + s.length;
        char[] buf = pack.toArray;
        uintptr_t i = indent;
        if(i > 0)
            buf[0..i] = ' ';
        buf[i .. $] = s;
        options.putDg(buf);
    }
}

/// output the XML declaration
void printXmlDeclaration(AttributeMap attr, StringPutDg putOut)
{
    if (attr.length == 0)
        return;

    char[] xmldec;
    Array!char	app;


    void putAttribute(string attrname)
    {
        string* pvalue = attrname in attr;
        if (pvalue !is null)
        {
            app.put(' ');
            app.put(attrname);
            app.put("=\"");
            app.put(*pvalue);
            app.put('\"');
        }
    }
    app.put("<?xml");
    putAttribute("version");
    putAttribute("standalone");
    putAttribute("encoding");
    app.put("?>");
    putOut(app.unique);
}

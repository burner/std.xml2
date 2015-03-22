
module xmlp.xmlp.arraydombuild;

import xmlp.xmlp.arraydom;
import xmlp.xmlp.tagvisitor;

import xmlp.xmlp.sliceparse;
import xmlp.xmlp.xmlparse;
import xmlp.xmlp.doctype;

import xmlp.xmlp.subparse, xmlp.xmlp.parseitem, xmlp.xmlp.charinput;
import xmlp.xmlp.builder;
import alt.zstring;
import std.stream;
import std.variant;

Document buildArrayDom(IXMLParser xp)
{
	auto tv = new TagVisitor(xp);
	auto xbuild = new ArrayDomBuilder();
	auto result = new Document();
	xbuild.init(result);
	tv.defaults.setBuilder(xbuild);
	tv.parseDocument();
	return result;
}


Document loadString(string xml, bool validate = true, bool useNamespaces = false)
{
    IXMLParser cp = new XmlStringParser(xml);
	cp.validate(validate);
	return buildArrayDom(cp);
}


/** Parse from a file $(I path).
Params:
path = System file path to XML document
validate = true to invoke ValidateParser with DOCTYPE support,
false (default) for simple well formed XML using CoreParser
useNamespaces = true.  Creates ElementNS objects instead of Element for DOM.


*/
Document loadFile(string path, bool validate = true, bool useNamespaces = false)
{
    auto s = new BufferedFile(path);
    auto sf = new XmlStreamFiller(s);
	IXMLParser cp = new XmlDtdParser(sf,validate);
	cp.setParameter(xmlAttributeNormalize,Variant(true));
	return buildArrayDom(cp);

}

/// collector callback class, used with XmlVisitor
class ArrayDomBuilder : Builder
{
    Array!Element		elemStack_;
    Element			    root;
    Element				parent;

    this()
    {
    }

    this(Element d)
    {
        init(d);
    }
    void init(Element d)
    {
        root = d;
        parent = root;
        elemStack_.clear();
        elemStack_.put(root);
    }
    override void init(ref XmlReturn ret)
    {
        auto e = createElement(ret);
        init(e);
    }
    override void pushTag(ref XmlReturn ret)
    {
        auto e = createElement(ret);
        elemStack_.put(e);
        parent.appendChild(e);
        parent = e;
    }
    override void singleTag(ref XmlReturn ret)
    {
        parent ~= createElement(ret);
    }

    override void popTag(ref XmlReturn ret)
    {
        elemStack_.popBack();
        parent =  (elemStack_.length > 0) ? elemStack_.back() : null;
    }
    override void text(ref XmlReturn ret)
    {
        parent ~= new Text(ret.scratch);
    }
    override void cdata(ref XmlReturn ret)
    {
        parent ~= new CData(ret.scratch);
    }
    override void comment(ref XmlReturn ret)
    {
        parent.appendChild(new Comment(ret.scratch));
    }
    override void processingInstruction(ref XmlReturn ret)
    {
		auto rec = ret.attr.atIndex(0);
		parent.appendChild(new ProcessingInstruction(rec.id, rec.value));
    }
    override void xmldec(ref XmlReturn ret)
    {
		root.attr = ret.attr;
    }
	override void explode(bool del)
	{
		if (del)
			elemStack_.free();
		else
			elemStack_.forget();
		super.explode(del);
	}
}

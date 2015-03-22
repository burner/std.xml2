/**

Reusing this module name, because running out of module names.
Attempt to integrate the CoreParser and the DomBuilder,
as an entire integrated class, to see if some overheads of
communication between can improve performance.

In fact it may resemble the original std.xml

Cycle through parse, if used, will be checked only at low level.

Authors: Michael Rynn
Licence: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)

The class does not support the IXMLParser interface,
because lower level access to the parse is not allowed.

Will use ParseSource, in module xmlsource, as a base.

*/

module xmlp.xmlp.domparse;

import xmlp.xmlp.linkdom;
import xmlp.xmlp.elemvalidate;
import xmlp.xmlp.subparse;
import xmlp.xmlp.error;
import xmlp.xmlp.coreprint;
import xmlp.xmlp.parseitem;
import xmlp.xmlp.charinput;
import xmlp.xmlp.xmlchar;

import std.stream;
import std.array;
import std.exception;
import std.variant;
import std.conv;
import std.string;
import std.stdio;
import xmlp.xmlp.dtdvalidate;
import xmlp.xmlp.dtdtype;
import xmlp.xmlp.doctype;
import xmlp.xmlp.entitydata, xmlp.xmlp.validate;
import alt.zstring;
import std.utf;

alias std.conv.text		concat;

/**
    Use IXMLParser and linkdom to make entire Document
*/
private struct ParseLevel {
	Element		elem;
	ElementDef	edef;
};

version (GC_STATS)
{
	import alt.gcstats;
}

class  DocumentBuilder
{
version(GC_STATS)
{
	mixin GC_statistics;
	static this()
	{
		setStatsId(typeid(typeof(this)).toString());
	}
}
protected:

	XmlReturn	ret;
	ParseLevel  level;

	Array!ParseLevel			parseStack_;
	IXMLParser					xp_;
    DTDValidate		            dtd_;
    // document to build and hold configuration properties
    Document		            doc_;
	Node						parent_;
    NameSpaceSet				nsSet_;
	bool						namespaceAware_;

public:
	this()
	{
		version(GC_STATS)
			gcStatsSum.inc();		
	}

	~this()
	{
		explode(false);
		version(GC_STATS)
			gcStatsSum.dec();
	}
	void explode(bool del)
	{
		parseStack_.free(del);
		xp_ = null;
		dtd_ = null;
		doc_ = null;
	}

    /// delegate handler
    bool namespaces() const
    {
        return namespaceAware_;
    }
    void namespaces(bool value)
    {
        auto config = doc_.getDomConfig();
        config.setParameter("namespaces",Variant(value));
        namespaceAware_ = value;
    }
    private void setParser(IXMLParser p)
    {
        xp_ = p;
        if (xp_ !is null)
        {
            xp_.setPrepareThrowDg(&onParserError);
            xp_.setReportInvalidDg(&onReportInvalid);
			xp_.setProcessingInstructionDg(&onProcessingInstruction);
			// It will be done/called here, not to do twice.
			xp_.setParameter(xmlAttributeNormalize,Variant(false));
        }
    }

    protected void checkSplitName(string aName, ref string nsPrefix, ref string nsLocal)
    {
        uintptr_t sepct = splitNameSpace(aName, nsPrefix, nsLocal);

        if (sepct > 0)
        {
            if (sepct > 1)
                xp_.throwNotWellFormed(concat("Multiple ':' in name ",aName));
            if (nsLocal.length == 0)
                xp_.throwNotWellFormed(concat("':' at end of name ",aName));
            if (nsPrefix.length == 0)
                xp_.throwNotWellFormed(concat("':' at beginning of name ",aName));
        }
    }
    private void push_invalid(string msg)
    {
       xp_.getErrorStack().pushMsg(msg, ParseError.invalid);
    }

    private void push_error(string msg)
    {
        xp_.getErrorStack().pushMsg(msg, ParseError.error);
    }

    /// The current parse state is restored, prior to a context pop

    void reviewElementNS(ElementNS elem, NameSpaceSet pnss)
    {
        // now review element name itself
        string prefix;
        string localName;
        string nsURI;

        checkSplitName(elem.getNodeName(), prefix, localName);

        bool needNS = (prefix.length > 0);

        if (pnss !is null)
        {
            auto pdef = prefix in pnss.nsdefs_;
            if (pdef !is null)
            {
                auto rdef = *pdef;
                nsURI = rdef.getValue();
                if (nsURI.length == 0)
                {
                    push_error(concat("Namespace ",prefix," is unbound"));
                }
                else
                {
                    elem.setURI(nsURI);
                    needNS = false;
                }
            }

        }
        if (needNS)
        {
            if (prefix == "xmlns")
            {
                push_error(concat(elem.getNodeName()," Elements must not have prefix xmlns"));
            }
            xp_.throwNotWellFormed(concat("No namespace found for ", elem.getNodeName()));
        }
        checkErrorStack();
    }

    private void checkErrorStack()
    {
        ErrorStack estk = xp_.getErrorStack();
        // check for errors and invalid
        switch (estk.errorStatus)
        {
			case ParseError.invalid:
				if (xp_.validate())
					xp_.reportInvalid();
				break;
			case ParseError.error:
				xp_.throwParseError("Namespace error");
				break;
			case ParseError.fatal:
				xp_.throwNotWellFormed("Namespace error");
				break;
			default:
				break;
        }
    }
    NameSpaceSet reviewAttrNS(ElementNS elem, NameSpaceSet pnss)
    {
        // A namespace definition <id> exists if there is a xmlns:<id>="URI" in the tree root.
        // for each attribute, check if the name is a namespace specification

        NamedNodeMap amap = elem.getAttributes();
        if (amap is null)
            return pnss;

        AttrNS rdef;			// attribute which defines a namespace
        AttrNS* pdef;
        NameSpaceSet nss;
        // attributes which are not namespace declarations
        AttrNS[]     alist;
        string prefix;
        string nsURI;
        string localName;
        string name;

        auto app = appender(alist);


        bool validate =  xp_.validate();
        int nslistct = 0;

        bool isNameSpaceDef;
        // collect any new namespace definitions
        double xml_version = xp_.xmlVersion();

        // divide the attributes into those that specify namespaces, and those that do not.
        foreach(a ; amap)
        {
            AttrNS nsa = cast(AttrNS) a;
            name = nsa.getName();

            checkSplitName(name, prefix, localName);

            if (prefix.length > 0)
            {
                isNameSpaceDef = (cmp("xmlns",prefix) == 0);
            }
            else
            {
                isNameSpaceDef = (cmp("xmlns",name) == 0);
            }

            if (isNameSpaceDef)
            {
                if (nss is null)
                {
                    nss = new NameSpaceSet(elem, pnss);
                    pnss = nss;
                }

                bool bind = true;
                nsURI = nsa.getValue();
                localName = nsa.getLocalName();
                if (nsURI.length == 0)
                {
                    if (localName.length > 0)
                    {
                        // default namespace unbinding ok for 1.0
                        bind = false;
                        // is it an error to unbind a non-existing name space?
                        nss.nsdefs_[localName] = nsa; // register as unbound
                    }
                    else
                    {
                        // invalid for 1.0 ?
                        if (xml_version == 1.0)
                            xp_.throwNotWellFormed(concat("Empty name space URI in ",elem.getTagName()));
                    }
                }
                else
                {
                    // A bit of validation for the URI / IRI
                    if (xml_version > 1.0)
                    {
                        if (!isNameSpaceIRI(nsURI))
                            xp_.throwParseError(concat("Malformed IRI ", nsURI));
                    }
                    else if(!isNameSpaceURI(nsURI))
                    {
                        xp_.throwParseError(concat("Malformed URI ", nsURI));
                    }
                }
                if (bind)
                {
                    // reserved namespaces check
                    if (prefix.length == 0)
                    {
                        if (localName == "xmlns")
                        {
                            if (nsURI == xmlNamespaceURI || nsURI == xmlnsURI)
                                xp_.throwNotWellFormed(concat("Cannot set default namespace to ",nsURI));
                        }
                    }
                    else if (prefix == "xml")
                    {
                        if (nsURI != xmlNamespaceURI)
                            xp_.throwNotWellFormed(concat("xml namespace URI ",nsURI," is not the reserved value ",xmlNamespaceURI));

                    }

                    else if (prefix == "xmlns")
                    {
                        if (localName == "xmlns")
                        {
                            xp_.throwNotWellFormed(concat("xmlns is reserved, but declared with URI: ", nsURI));
                        }
                        else if (localName == "xml")
                        {
                            if (nsURI != xmlNamespaceURI)
                                xp_.throwNotWellFormed(concat("xml prefix declared incorrectly ", nsURI));
                            else if (validate)
                                xp_.getErrorStack().pushMsg(concat("xml namespace URI ",xmlNamespaceURI," must only have prefix xml"),ParseError.invalid);
                            goto DO_BIND;
                        }
                        else if (localName == "xml2")
                        {
                            if (validate)
                                xp_.getErrorStack().pushMsg(concat("Binding a reserved prefix xml2"),ParseError.invalid);
                        }

                        if (nsURI == xmlNamespaceURI)
                        {
                            xp_.throwNotWellFormed(concat("xml namespace URI cannot be bound to another prefix ", nsURI));
                        }
                        if (nsURI == xmlnsURI)
                        {
                            xp_.throwNotWellFormed(concat("xmlns namespace URI cannot be bound to another prefix ", nsURI));
                        }
                    }
DO_BIND:
                    nss.nsdefs_[localName] = nsa; // register as bound to URI value
                }
            }
            else
            {
                app.put(nsa);
            }
        }
        bool needNS;
        alist = app.data();
        // assign namespace URIS

        string noNSMsg(AttrNS ans)
        {
            return concat("No namespace for attribute ",ans.getName());
        }
        foreach(nsa ; alist)
        {
            prefix = nsa.getPrefix();
            needNS = true;
            if (pnss !is null)
            {
                pdef = prefix in pnss.nsdefs_;
                if (pdef !is null)
                {
                    rdef = *pdef;

                    if (rdef.getValue() is null)
                        push_error(concat("Namespace ",prefix," is unbound"));
                    nsa.setURI(rdef.getValue());
                    needNS = false;
                }
            }

            if (needNS)
            {
                if (prefix == "xml")
                {
                    // special allowance
                    if (validate)
                    {
                        push_invalid("Undeclared namespace 'xml'");
                    }
                }
                else if (prefix.length == 0)
                {
                    if (validate)
                        xp_.getErrorStack().pushMsg(noNSMsg(nsa), ParseError.invalid);
                }
                else
                     xp_.throwNotWellFormed(noNSMsg(nsa));
            }

        }

        // pairwise check, prove no two attributes with same local name and different prefix have same URI
        if (pnss !is null)
        {
            for(int nix = 0; nix < alist.length; nix++)
            {
                for(int kix = nix+1; kix < alist.length; kix++)
                {
                    AttrNS na = alist[nix];
                    AttrNS ka = alist[kix];

                    if (na.getLocalName() != ka.getLocalName())
                    {
                        continue;
                    }

                    // same local name and prefix is a duplicate name, so the prefixes must be be different.


                    if (na.getNamespaceURI() == ka.getNamespaceURI())
                    {
                        string errMsg = concat("Attributes with same local name and default namespace: ",na.getNodeName(), " and ", ka.getName());

                        if (na.getPrefix() is null || ka.getPrefix() is null)
                            push_invalid(errMsg);
                        else
                            xp_.throwNotWellFormed(errMsg);
                    }
                }
            }
        }
        checkErrorStack();

        return pnss;
    }
	void init()
	{
		parseStack_.reserve(16);
	}

public:
	@property Document document()
	{
		return doc_;
	}
	/// one chance to set own Document object
	this(IXMLParser p, Document d = null)
	{
		doc_ = (d is null) ? new Document() : d;
		parent_ = doc_;
		setParser(p);
		init();
		version(GC_STATS)
			gcStatsSum.inc();
	}

	void popTag(ref XmlReturn ret)
	{
		if ((nsSet_ !is null) && (nsSet_.elem_ == level.elem))
			nsSet_ = nsSet_.parent_;
		if (level.edef !is null)
			validElementContent(level.edef, level.elem, xp_.getErrorStack());
		level = parseStack_.back();
		parseStack_.popBack();
		parent_ = (level.elem is null) ? doc_ : level.elem;
	}
	void emptyTag(ref XmlReturn ret)
	{
		auto edef = (dtd_ is null) ? null : dtd_.getElementDef(ret.scratch);
		auto child = createElement(ret);
		if (edef !is null)
			validElementContent(edef, child, xp_.getErrorStack());
		parent_.appendChild(child);
	}
	Node getParent()
	{
		return parent_;
	}
	void pushTag(ref XmlReturn ret)
	{
		parseStack_.put(level);
		level.elem = createElement(ret);
		parent_.appendChild(level.elem);
		level.edef = (dtd_ is null) ? null : dtd_.getElementDef(ret.scratch);
		parent_ = level.elem;
	}
	void text(ref XmlReturn ret)
	{
		parent_.appendChild(new Text(ret.scratch));	
	}
	void processingInstruction(ref XmlReturn ret)
	{
		auto rec = ret.attr.atIndex(0);
		parent_.appendChild(new ProcessingInstruction(rec.id,rec.value));
	}
	void cdata(ref XmlReturn ret)
	{
		auto n = ((level.edef !is null) && (level.edef.hasPCData))
			? doc_.createTextNode(ret.scratch)
			: doc_.createCDATASection(ret.scratch);
		parent_.appendChild(n);
	}
	void comment(ref XmlReturn ret)
	{
		parent_.appendChild(new Comment(ret.scratch));
	}
	void xmldec(ref XmlReturn ret)
	{
		if (parseStack_.length > 0)
			xp_.throwNotWellFormed("illegal xml declaration");

		auto xvalue = ret.attr.get("version",null);
		if (xvalue !is null)
		{
			doc_.setXmlVersion(xvalue);
		}
		xvalue = ret.attr.get("encoding",null);
		if (xvalue !is null)
		{
			doc_.setInputEncoding(xvalue);
			doc_.setEncoding(xvalue); // why 2?
		}
		xvalue = ret.attr.get("standalone",null);
		if (xvalue !is null)
			doc_.setXmlStandalone(xvalue=="yes");
		
	}
	void dtd(ref XmlReturn ret)
	{
		dtd_ = cast(DTDValidate) ret.node;

		auto doctype = new DocumentType(dtd_.id_);
		// TODO: make DocumentType NameNodeMap for entities, notations, internal subset (YUK)
		doctype.setDTD(dtd_);
		doc_.appendChild(doctype);
	}

	void initParse()
	{
		xp_.initParse();
		parent_ = doc_;

		DOMConfiguration conf = doc_.getDomConfig();
		auto list = conf.getParameterNames();
		foreach(s ; list.items())
		{
			auto v = conf.getParameter(s);
			xp_.setParameter(s,v);
		}
		namespaceAware_ = xp_.namespaces();
	}

	void onProcessingInstruction(string pitarget, string pidata)
	{
		doc_.appendChild(new ProcessingInstruction(pitarget,pidata));
	}

	@property final uintptr_t stackLevel()
	{
		return  parseStack_.length;
	}
	
	void clear()
	{
	 	parseStack_.clear();
	}

	void buildUntil(uintptr_t endLevel)
	{
		for(;;)
        {
			if (!xp_.parse(ret))
			{
				clear();
				return;
			}
            switch(ret.type)
            {
				case XmlResult.STR_TEXT:
					text(ret);
					break;
				case XmlResult.TAG_START:
					pushTag(ret);
					break;
				case XmlResult.TAG_SINGLE:
					emptyTag(ret);
					break;
				case XmlResult.TAG_END:
					popTag(ret);
					if (endLevel > parseStack_.length)
						return;
					break;
				case XmlResult.STR_CDATA:
					cdata(ret);
					break;
				case XmlResult.STR_COMMENT:
					comment(ret);
					break;
				case XmlResult.STR_PI:
					processingInstruction(ret);
					break;
				case XmlResult.DOC_TYPE:
					dtd(ret);
					break;
				case XmlResult.XML_DEC:
					xmldec(ret);
					break;
				default:
					break;
            }
		}
	}

    /**
        Parse till exit from current level,
        without fussing over callbacks.
        Do a full document build
    */
    void buildContent()
    {
		initParse();
		buildUntil(0);
    }



    Element createElement(ref XmlReturn ret)
    {
        auto node = doc_.createElement(ret.scratch);
        
        if (dtd_ !is null)
        {
            dtd_.validateAttributes(xp_, ret);
        }
        else
        {
            normalizeAttributes(xp_,ret);
        }

		foreach(n,v ; ret.attr)
        {
			node.setAttribute(n,v);
        }

        if (namespaceAware_)
        {
            if (xp_.namespaces())
            {
                ElementNS ens = cast(ElementNS) node;
                if (ens)
                {
                    nsSet_ = reviewAttrNS(ens, nsSet_);
                    reviewElementNS(ens, nsSet_);
                }
            }
        }
        return node;
    }

    ParseError onParserError(ParseError ex)
    {
        DOMConfiguration conf = doc_.getDomConfig();
        Variant v = conf.getParameter("error-handler");
        DOMErrorHandler* peh = v.peek!(DOMErrorHandler);
        if (peh !is null)
        {
            auto eh = *peh;

            //TODO: is it ever really going to be null?
            string msg =  ex.toString();

            // supporting DOMError
            DOMError derr = new DOMError(msg);
            SourceRef spos;
            xp_.getLocation(spos);

            DOMLocator loc = new DOMLocator();
            loc.charsOffset = spos.charsOffset;
            loc.lineNumber = spos.lineNumber;
            loc.colNumber = spos.colNumber;

            derr.setLocator(loc);
            derr.setException(ex);

            int severity;

            switch(ex.severity)
            {
            case ParseError.error:
                severity = DOMError.SEVERITY_ERROR;
                break;
            case ParseError.fatal:
                severity = DOMError.SEVERITY_FATAL_ERROR;
                break;
            default:
                severity = DOMError.SEVERITY_WARNING;
                break;
            }

            derr.setSeverity(severity);
            eh.handleError(derr);
        }
        return ex;
    }
    private void onReportInvalid(string msg)
    {
        // use the DOMError to report invalid, not necessarily fatal errors.
        DOMConfiguration conf = doc_.getDomConfig();
        Variant v = conf.getParameter("error-handler");
        DOMErrorHandler eh = *v.peek!(DOMErrorHandler);
        if (eh !is null)
        {
            auto derr = makeDOMError(msg);
            derr.setSeverity(DOMError.SEVERITY_WARNING);
            eh.handleError(derr);
        }
    }
    private DOMError makeDOMError(string msg)
    {
        DOMError derr = new DOMError(msg);
        SourceRef spos;
        xp_.getLocation(spos);

        DOMLocator loc = new DOMLocator();
        loc.charsOffset = spos.charsOffset;
        loc.lineNumber = spos.lineNumber;
        loc.colNumber = spos.colNumber;

        derr.setLocator(loc);
        derr.setException(null);
        return derr;
    }

}


static Document loadString(string path, bool validate = true, bool useNamespaces = false)
{
    IXMLParser ix = validate ? parseXmlStringValidate(path) : parseXmlString(path);

    DocumentBuilder dp =  new DocumentBuilder(ix);
    dp.namespaces(useNamespaces);
    dp.buildContent();
    return dp.document;
}


/** Parse from a file $(I path).
Params:
    path = System file path to XML document
    validate = true to invoke ValidateParser with DOCTYPE support,
                false (default) for simple well formed XML using CoreParser
    useNamespaces = true.  Creates ElementNS objects instead of Element for DOM.


*/
static Document loadFile(string path, bool validate = true, bool useNamespaces = false)
{
    IXMLParser ix = validate ? parseXmlFileValidate(path) : parseXmlFile( path);
    DocumentBuilder dp = new DocumentBuilder(ix);
    dp.namespaces(useNamespaces);
    dp.buildContent();
    return dp.document;

}
/// implementation for XmlDtdParser, string source
IXMLParser parseXmlString(string src)
{
    auto sf = new SliceFill!(char)(src);
    IXMLParser cp = new XmlDtdParser(sf, false);
    return cp;
}


/// implementation for XmlDtdParser, string source, validate
IXMLParser parseXmlStringValidate(string src)
{
    auto sf = new SliceFill!(char)(src);
    IXMLParser cp = new XmlDtdParser(sf, true);
    return cp;
}

/// implementation for XmlDtdParser, file source
IXMLParser parseXmlFile(string srcpath)
{
    auto s = new BufferedFile(srcpath);
    auto sf = new XmlStreamFiller(s);
    IXMLParser cp = new XmlDtdParser(sf, false);
    return cp;
}

/// implementation for XmlDtdParser, file source, validate
IXMLParser parseXmlFileValidate(string srcpath)
{
    auto s = new BufferedFile(srcpath);
    auto sf = new XmlStreamFiller(s);
    IXMLParser cp = new XmlDtdParser(sf, true);
    return cp;
}

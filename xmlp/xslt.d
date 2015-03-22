/**
	Transforms using XPath 1.0 implementation.
	Uses xmlp.xmlp package. 
    
	
Authors: Michael Rynn
Licence: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Distributed under the Boost Software License, Version 1.0.

Version:  0.1

A  test transform toy class 

*/
module std.xpath.transform;

import std.stdio;
import xmlp.xml2;
import xmlp.xpath.syntax;
import std.exception;
import xmlp.xmlp.array;

import std.conv;
import xmlp.xmlp.coreprint;
import std.ctype;

// this could be a resource?	
string inputXml;
string inputXsl;
string outputXml;

/// might have lots of these
class XSLTError : Exception {
	this(string msg)
	{
		super(msg);
	}
}

void ThrowTemplateMissing(string name)
{
	throw new XSLTError(text("Template match not found for ", name));
}

alias KeyValueBlock!(string,Node)	KeyNodeBlock;

/** Requires transform document, input and output paths.
	Tracks templates and state during transformation.
*/
class XSLTransform {
	/** gets transformed text back in chunks
	
	----
	alias void delegate(const(char)[] text) OutputDg;
	----
	*/
	alias void delegate(const(char)[] text) OutputDg;
	
	Element[string]	  rootTemplates;
	OutputDg		  emitDg;
	Document		  sourceDoc;
	Document		  styleDoc;
	PathExpression[string] cachePE;
	bool[string]	  spacePreserve;
	bool[string]	  spaceStrip;
	
	/// PathExpression starts with path
	static PathExpression getPath(string p)
	{
		XPathParser xpp;
		return  xpp.prepare(p,InitState.IN_PATH);
	}
	/// PathExpression starts with predicate
	static PathExpression getPredicate(string p)
	{
		XPathParser xpp;
		return  xpp.prepare(p,InitState.IN_PREDICATE);
	}	
	
	
	string selectValue(string p, Element contextNode)
	{
		NodeList results = selectResult(p, contextNode);
		if (results.getLength() > 0)
		{
			Node n = results[0];
			return  (n.getNodeType()==NodeType.Element_node) ? n.getTextContent() : n.getNodeValue();
		}
		return null;
	}
	
	bool testCondition(string p, Element contextNode)
	{
		PathExpression exp;
		auto ppe = p in cachePE;
		if (ppe is null)
		{
			exp = getPredicate(p);
			cachePE[p] = exp;
		}
		else
		{
			exp = *ppe;
		}
		
		NodeList results = selectResult(p, contextNode);
		return results.getLength() > 0;
	}
	
	NodeList selectResult(string p, Element contextNode)
	{
		PathExpression exp;
		auto ppe = p in cachePE;
		if (ppe is null)
		{
			exp = getPath(p);
			cachePE[p] = exp;
		}
		else
		{
			exp = *ppe;
		}
		return run(exp, contextNode);
	}
	
	Element firstChildWithName(Element p, string name)
	{
		Node n = p.getFirstChild();
		while (n !is null)
		{
			if ((n.getNodeType() == NodeType.Element_node) && (n.getNodeName() == name))
			{
				return cast(Element) n;
			}
			n = n.getNextSibling();
		}
		return null;
	}
	
	void processTemplate(Element te, Element contextNode)
	{
		XMLOutOptions	outopt;
		outopt.indentStep = 0; // no auto indent;
		auto tp = TagPrinter(outopt);
		
		void doTemplateMatch(Element choose)
		{
			auto pte = choose.getNodeName in rootTemplates;
			if (pte !is null)
			{
				auto ate = *pte;
				processTemplate(ate,choose);
			}	
		}
		
		void doNodeList(NodeList results)
		{
			foreach(n ; results)
			{
				Element newContext = cast(Element) n;
				doTemplateMatch(newContext);
			}				
		}
		
		Node ch = te.getFirstChild();
		while (ch !is null)
		{
			switch(ch.getNodeType())
			{
			case NodeType.Text_node:
				emitDg(ch.getNodeValue());
				break;
			case NodeType.Element_node:
				string prefix = ch.getPrefix();
				Element e = cast(Element) ch;
				if (prefix == "xsl")
				{
					string fname = e.getLocalName();
					if (fname == "for-each")
					{
						NodeList results = selectResult(e.getAttribute("select"), contextNode);
						
						if (results.getLength() > 0)
						{
							// check for sorting
							Element sortOrder = firstChildWithName(e,"xsl:sort");
							if (sortOrder !is null)
							{
								string pathSortExp = sortOrder.getAttribute("select");
								// tricky.. need to get value of path expression for each node.
								// associate that result with each node.
								// sort node array based associated result
								KeyNodeBlock  nb;
								
								foreach(n ; results)
								{
									Element newContext = cast(Element) n;
									string ndata = selectValue(pathSortExp,newContext);
									nb.put(KeyNodeBlock.BlockRec(ndata,n));
								}
								nb.sort();
								results.setItems(nb.getValues(results.items));
							}
						}
						
						foreach(n ; results)
						{
							Element newContext = cast(Element) n;
							processTemplate(e, newContext);
						}
					}
					else if (fname == "value-of")
					{
						NodeList results = selectResult(e.getAttribute("select"), contextNode);
						if (results.getLength() > 0)
						{
							Node n = results[0];
							string ndata = (n.getNodeType()==NodeType.Element_node) ? n.getTextContent() : n.getNodeValue();
							emitDg(ndata);
						}
					}
					else if (fname == "if")
					{
						bool valid = testCondition(e.getAttribute("test"),contextNode);
						if (valid)
						{
							processTemplate(e, contextNode);	
						}
					}
					else if (fname == "choose")
					{
						// first when true, or otherwise. TODO: detect when after otherwise?
						auto choose = e.getFirstChild();
						
						Element select;
						string selName;
						
						while (choose !is null)
						{
							bool valid = false;
							if (choose.getNodeType()==NodeType.Element_node && choose.getPrefix()=="xsl")
							{
								select = cast(Element) choose;
								selName = select.getLocalName();
								if (selName=="when" ? testCondition(select.getAttribute("test"),contextNode)
									: selName=="otherwise")
								{
									processTemplate(select, contextNode);
									break;
								}
							}
							choose = choose.getNextSibling();
						}
					}
					else if (fname == "apply-templates")
					{
						string selName = e.getAttribute("select");

						if (selName is null)
						{						
							// for each child see if a match applys
							auto choose = contextNode.getFirstChild();
							while(choose !is null)
							{
								if(choose.getNodeType()==NodeType.Element_node)
								{
									auto selElem = cast(Element) choose;
									NodeList results = selElem.getChildElements();
									if (results !is null)
										doNodeList(results);								
								}
								choose = choose.getNextSibling();
							}
						}
						else {
							// select at this context
							NodeList results = selectResult(selName, contextNode);
							if (results !is null)
								doNodeList(results);						
						}
					}
				}
				else {
					bool hasChildren = e.hasChildNodes();
					auto tag = e.getTagName();
					AttributeMap smap = toAttributeMap(e);
					string startElem = tp.startTag(tag,smap,false);
					if (!hasChildren)
					{
						emitDg(text(startElem,tp.endTag(tag)));
					}
					else {
						emitDg(startElem);
						processTemplate(e,contextNode);
						emitDg(tp.endTag(tag));
					}
					
				}
				break;
			default:
				break;
			
			}
			ch = ch.getNextSibling();
		}		
	}
	
	bool allWhiteSpace(string txt)
	{
		foreach(d ; txt)
			if (!isspace(d))
				return false;
		return true;
	}
	
	void stripChildWhiteSpace(Element e, bool stripOn)
	{
		string eName = e.getNodeName;
		if (eName in spacePreserve)
			stripOn = false;
		else if (eName in spaceStrip)
			stripOn = true;
		
		auto n = e.getFirstChild();
		while (n !is null)
		{
			auto next = n.getNextSibling();	
			switch(n.getNodeType)
			{
			case NodeType.Element_node:
				stripChildWhiteSpace(cast(Element)n, stripOn);
				break;
			case NodeType.Text_node:
				if (stripOn && allWhiteSpace(n.getNodeValue()))
					e.removeChild(n);
				break;
			default:
				break;
			}
			n = next;
			
		}
	}
	/// This is where it all happens
	void transform(Document xml, Document xsl, OutputDg dg)
	{
		emitDg = dg;
	// find the root template
		sourceDoc = xml;
		styleDoc = xsl;
		
		
		Element eDoc = styleDoc.getDocumentElement();
		NodeList rlist = eDoc.getElementsByTagName("xsl:template");
		foreach(r ; rlist)
		{
			Element e = cast(Element) r;
			string matchName = e.getAttribute("match");	
			// TODO : check dupliate matchName
			rootTemplates[matchName] = e;
		}
		// see if a match for "/"
		auto rootMatch = rootTemplates["/"];
		if (rootMatch is null)
		{
			ThrowTemplateMissing("/");
		}
		// also register document element with rootMatch, for default apply-templates
		Element srcRoot = sourceDoc.getDocumentElement();
		rootTemplates[srcRoot.getNodeName()] = rootMatch;
		
		// process each child.  Check for xsl instructions
		spacePreserve["xsl:text"] = true;
		spaceStrip["xsl:for-each"] = true;
		spaceStrip["xsl:sort"] = true;
		spaceStrip["xsl:if"] = true;
		spaceStrip["xsl:choose"] = true;
		spaceStrip["xsl:when"] = true;
		spaceStrip["xsl:otherwise"] = true;
		
		NodeList plist = eDoc.getElementsByTagName("xsl:preserve-space");	
		foreach(p ; plist)
		{
			auto pe = cast(Element) p;
			string eName = pe.getAttribute("elements");	
			spacePreserve[eName] = true;
		}
		plist = eDoc.getElementsByTagName("xsl:strip-space");	
		foreach(p ; plist)
		{
			auto pe = cast(Element) p;
			string eName = pe.getAttribute("elements");	
			spaceStrip[eName] = true;
		}
		// for each template child element, throw away whitespace
		foreach(ref v ; rootTemplates)
		{
			stripChildWhiteSpace(v, true);
		}
		Element contextNode = cast(Element) srcRoot.getParentNode();
		
		processTemplate(rootMatch, contextNode);
	}
}

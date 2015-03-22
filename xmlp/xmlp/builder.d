module xmlp.xmlp.builder;

import xmlp.xmlp.parseitem;

version (GC_STATS) import alt.gcstats;

import alt.zstring;

abstract class Builder {
	version (GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}
	version (GC_STATS)
	{
		this()
		{
			gcStatsSum.inc();
		}

		~this()
		{
			gcStatsSum.dec();
		}
	}


	/** 

	Called on the getting the starttag (or emptytag) element for which a Builder was setup.
	If XmlReturn.type is TAG_EMPTY
	then the endCall callback will be called directly after Builder method init, with the XmlResult reference!
	If the XmlReturn.type is TAG_START, then parsing will continue after the init method call.
	If the Builder object wants attribute information off its initial start tag, it must access them the init method,
	Note that pushTag is not called, for the tag name which triggered using the builder instance.
	Internally the XmlVisitor sets its Builder instance to the triggered builder, and routes XmlResult events to it,
	until it gets an endtag at the same element nesting level at which it was started. 
	The end callback returns the builder object to the user, in the XmlResult.node Object member, 
	after which it is forgotten by the XmlVisitor object.
	pushTag and popTag will only be called for children of the element that the builder was set up for. All other child content
	will call the appropriate method, test, cdata, comment, processing instruction.

	*/
	void init(ref XmlReturn ret){};
	/// A new child element, with content, in the scope of the builder
	void pushTag(ref XmlReturn ret){ debug(TRACE_BUILDER) writeln("Push tag ", ret.scratch);}
	/// A new child element with content ends in the scope of the builder
	void popTag(ref XmlReturn ret){ debug(TRACE_BUILDER) writeln("Pop tag ", ret.scratch);}
	/// A new child element, maybe with attributes, but no content, in the scope of the builder
	void singleTag(ref XmlReturn ret){}
	/// a text node child, in ret.scratch
	void text(ref XmlReturn ret){}
	/// a processing instruction child. target name in ret.names[0], rest in ret.values[0]
	void processingInstruction(ref XmlReturn ret){}
	/// another kind of text node child, in ret.scratch
	void cdata(ref XmlReturn ret){}
	/// another kind of text node child, in ret.scratch
	void comment(ref XmlReturn ret){}
	/// attributes in names and values of ret, should be only at root level
	void xmldec(ref XmlReturn ret){}
	
	/// pass a DTDValidate object?
	void doctype(ref XmlReturn ret){}

	void explode(bool del)
	{
		if (del)
			delete this;
	}	
}




/// Concantenate text nodes and cdata nodes, ignoring structure, children and everything else.
/// Ok for retrieving 1 text node only content
class TextCollector : Builder {
	Array!char buffer;

	override void init(ref XmlReturn ret)
	{
		buffer.clear();
	}
	override void text(ref XmlReturn ret)
	{
		buffer.put(ret.scratch);
	}

	override void cdata(ref XmlReturn ret)
	{
		buffer.put(ret.scratch);
	}

	override string toString()
	{
		return buffer.idup;
	}
}

/// Ok for retrieving a single 1 text node only content and nothing else.
/// Multiple content of any sort (even white space outside a CDATA), can stuff it up.
/// TODO: optional? check that one, and one only text method call was made
class SingleTextContent : Builder {
	string data;

	override void text(ref XmlReturn ret)
	{
		data = ret.scratch;
	}
	override string toString()
	{
		return data;
	}
}
/// Ok for retrieving a 1 text1 single CDATA content, and nothing else.
/// Multiple content of any sort (even white space outside a CDATA), will stuff it up.
class SingleCDATAContent : Builder {
	string data;

	override void cdata(ref XmlReturn ret)
	{
		data = ret.scratch;
	}

	override string toString()
	{
		return data;
	}
}

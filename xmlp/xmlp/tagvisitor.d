module xmlp.xmlp.tagvisitor;

/** 
Copyright: Michael Rynn 2012.
Authors: Michael Rynn
License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.


Maybe XmlVisitor isn't flexible enough.
---
// so to get text content of element, only, would set 
auto txtget = new TagBlock("author");
txtget[XmlResult.STR_TEXT] = (ref XmlReturn ret) {
	book.author = ret.scratch;
}
---

---
*/

import alt.zstring;
import xmlp.xml2;

import std.variant;
import xmlp.xmlp.builder;

class TagBlock {

version (GC_STATS)
{
	import alt.gcstats;
	mixin GC_statistics;
	static this()
	{
		setStatsId(typeid(typeof(this)).toString());
	}
}

	string			tagkey_;	// key
	ParseDg[XmlResult.DOC_END]		callbacks_;  // indexed by (XmlReturn.type - 1). Can have multiple per element.

	this(string tagName)
	{
		tagkey_ = tagName; // can be null?
		version (GC_STATS)
			gcStatsSum.inc();
	}

version (GC_STATS)
{
	~this()
	{
		gcStatsSum.dec();
	}
}
	void opIndexAssign(ParseDg dg, XmlResult rtype)
	in {
		assert(rtype < XmlResult.DOC_END);
	}
	body {
		callbacks_[rtype] = dg;
	}

	ParseDg opIndex(XmlResult rtype)
	in {
		assert(rtype < XmlResult.DOC_END);
	}
	body {
		return callbacks_[rtype];
	}

	bool didCall(ref XmlReturn ret)
	in {
		assert(ret.type < XmlResult.DOC_END);
	}
	body {
		auto dg = callbacks_[ret.type];
		if (dg !is null)
		{
			dg(ret);
			return true;
		}
		return false;
	}

}

/**
Yet another version of callbacks for XML.
---
auto tv = new TagVisitor(xmlParser);

auto mytag = new TagBlock("mytag");
mytag[XmlResult.TAG_START] = (ref XmlReturn ret){

};
mytag[XmlResult.TAG_SINGLEs] = (ref XmlReturn ret){

};
---

*/

class DefaultTagBlock {


	void opIndexAssign(ParseDg dg, XmlResult rtype)
	in {
		assert(rtype < XmlResult.ENUM_LENGTH);
	}
	body {
		callbacks_[rtype] = dg;
	}
	/// return a default call back delegate.
	ParseDg opIndex(XmlResult rtype)
	in {
		assert(rtype < XmlResult.ENUM_LENGTH);
	}
	body {
		return callbacks_[rtype];
	}	
	/// Sets all the callbacks of builder, except init.
	void setBuilder(Builder bob)
	{
		this[XmlResult.TAG_START] = &bob.pushTag;
		this[XmlResult.TAG_SINGLE] = &bob.singleTag;
		this[XmlResult.TAG_END] = &bob.popTag;
		this[XmlResult.STR_TEXT] = &bob.text;
		this[XmlResult.STR_PI] = &bob.processingInstruction;
		this[XmlResult.STR_CDATA] = &bob.cdata;
		this[XmlResult.STR_COMMENT] = &bob.comment;
		this[XmlResult.XML_DEC] = &bob.xmldec;
		this[XmlResult.DOC_TYPE] = &bob.doctype;

	}
	this()
	{

	}

	this(const DefaultTagBlock b )
	{
		callbacks_[0..$] = b.callbacks_[0..$];
	}

	ParseDg[XmlResult.ENUM_LENGTH]	callbacks_;  // all

}

private struct ParseLevel
{
	string		tagName;
	TagBlock	handlers_;
}

class TagVisitor  {
	// Ensure Tag name, and current associated TagBlock are easily obtained after TAG_END.

	Array!ParseLevel			parseStack_;
	ParseLevel					current_; // whats around now.
	protected IXMLParser		xp_;
	intptr_t					level_; // start with just a level counter.
	TagBlock[string]			tagHandlers_;
	bool						handlersChanged_;  // flag to recheck stack TagBlock
	bool						called_;			// some handler was called.
public:
	DefaultTagBlock				defaults;

	/// Experimental and dangerous for garbage collection. No other references must exist.
	version (GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}
	/// create, add and return new TagBlock
	TagBlock create(string tag)
	{
		auto result = new TagBlock(tag);
		tagHandlers_[tag] = result;
		return result;
	}
	
	/// convenience for single delegate assignments for a tag string
	/// Not that null tag will not be called, only real tag names are looked up.
	/// Delegate callbacks can be set to null
	void opIndexAssign(ParseDg dg, string tag, XmlResult rtype)
	{
		auto tb = tagHandlers_.get(tag,null);
		if (tb is null) 
		{
			tb = create(tag);
			tagHandlers_[tag] = tb;
		}
		tb[rtype] = dg;
	}
	/// return value of a named callback
	ParseDg opIndex(string tag, XmlResult rtype)
	{
		auto tb = tagHandlers_.get(tag, null);
		if (tb !is null)
			return tb[rtype];
		return null;
	}
	/// return block of call backs for tag name
	void opIndexAssign(TagBlock tb, string tag)
	{
		if (tb is null)
			tagHandlers_.remove(tag);
		else
			tagHandlers_[tag] = tb;
	}	/// return block of call backs for tag name
	TagBlock opIndex(string tag)
	{
		return tagHandlers_.get(tag, null);
	}
	/// set a block of callbacks for tag name, using the blocks key value.
	void put(TagBlock tb)
	{
		tagHandlers_[tb.tagkey_] = tb;
		handlersChanged_ = true;
	}
	/// set a default call back delegate.

	/// remove callbacks for a tag name.
	void remove(string tbName)
	{
		tagHandlers_.remove(tbName);
		handlersChanged_ = true;
	}
	/// Help the garbage collector, done with this object
	void explode(bool del)
	{
		xp_ = null;
		if (del && (tagHandlers_.length > 0))
		{
			foreach(k ; tagHandlers_.keys())
			{
				tagHandlers_.remove(k);
			}
		}
	}


	/// Construct with IXMLParser interface
	this(IXMLParser xp)
	{
		xp_ = xp;
		version(GC_STATS)
			gcStatsSum.inc();
		// This is a low level handler.
		xp_.setParameter(xmlAttributeNormalize,Variant(true));
		defaults = new DefaultTagBlock();
	}
	
	~this()
	{
		explode(false);
		version(GC_STATS)
			gcStatsSum.dec();
	}

    /** Do a callback controlled parse of document

	*/
    void parseDocument()
    {
        XmlReturn   ret;
        // Has to be depth - 1, otherwise premature exit
        intptr_t    startLevel = parseStack_.length;
		//intptr_t	builderLevel = 0;

        while(xp_.parse(ret))
        {
			called_ = false;
			switch(ret.type)
			{
				case XmlResult.TAG_START:
					// a new tag.
					parseStack_.put(current_);
					current_.tagName = ret.scratch;
					current_.handlers_ = tagHandlers_.get(ret.scratch,null);
					if (current_.handlers_ !is null)
						called_ = current_.handlers_.didCall(ret);
					break;
				case XmlResult.TAG_SINGLE:
					// no push required, but check after
					auto tb = tagHandlers_.get(ret.scratch,null);
					if (tb !is null)
					{
						called_ = tb.didCall(ret);
					}
					break;
				case XmlResult.TAG_END:
					if (current_.handlers_ !is null)
						called_ = current_.handlers_.didCall(ret);
					current_ = parseStack_.back();
					parseStack_.popBack();
					if (handlersChanged_)
						current_.handlers_ = tagHandlers_.get(current_.tagName,null);
					if (parseStack_.length < startLevel)
						return; // loopbreaker
					break;
				default:
					if (ret.type < XmlResult.DOC_END)
					{
						if (current_.handlers_ !is null)
							called_ = current_.handlers_.didCall(ret);
					}
					break;
			}
			if (!called_)
			{
				auto dg = defaults.callbacks_[ret.type];
				if (dg !is null)
					dg(ret);
			}
        }
    }
}

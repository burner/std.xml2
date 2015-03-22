/**
Authors: Michael Rynn
License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.

*/
module  xmlp.xmlp.xmlvisitor;

pragma(msg, "Notice: This module is deprecated. Replaced by xmlp.xmlp.tagvisitor");


version(posix) import core.sys.posix.time;
import std.typecons;
import std.conv;
version(unittest) import std.stdio;

deprecated:

import xmlp.xmlp.builder;
import std.variant;
import xmlp.xmlp.subparse, xmlp.xmlp.parseitem;
import alt.zstring;

//version=ExplodeDeletes;
version(GC_STATS)
	import alt.gcstats;
/// delegate handler. Returns parse result, allows setting more XmlVisitor callbacks


/// Standard keys for non-element tags
immutable XmlKey XmlAllKey = XmlKey(null, XmlResult.RET_NULL); // callback on everything
immutable XmlKey XmlPIKey = XmlKey(null,XmlResult.STR_PI);
immutable XmlKey XmlDecKey = XmlKey(null,XmlResult.XML_DEC);
immutable XmlKey XmlTextKey = XmlKey(null,XmlResult.STR_TEXT);
immutable XmlKey XmlCDATAKey = XmlKey(null,XmlResult.STR_CDATA);
immutable XmlKey XmlCommentKey = XmlKey(null,XmlResult.STR_COMMENT);


/**

The idea of a builder, is that it can be set to manage the XmlReturn parser events.

If a builder is associated with an Element tag name, and a callback delegate, then at the beginning of the tag,
its init method is called, and all parse events are redirected to it until the tag ends, and the callback is finally called.


This makes it ideal to be a resuable agent to selectively collect child content.  The simplest common case is the single text
value element.  In reusing the XmlReturn structure to supply the parsed values, 
the element name is returned in the scratch_ field, attribute names and values are already, used,
and the only remaining field is the Object "node" field. So the builder object will be returned in the node field.
For the TextCollector specialisation, the string value is accessible using the Object overridden toString method.


The Builder interface methods --


For any child elements ending with non-empty content, the popTag is called.
For a child element with detected no content <tag [attributes] ></tag>   or <tag [attributes] />, emptyTag is called.
There currently a possible exception to this, if the XmlParser class parser is configured with parameter called "fragment",
setParameter("fragment",Variant(true)), the XmlParser will not check for first form of empty tag,
at the document element level. This is a hack to assist jabber xml document messaging , and not likely to be used otherwise.
The jabber fragment parameter is not available for the XmlStringParser.


*/
debug = TRACE_BUILDER;

debug (TRACE_BUILDER)
{
	import std.stdio;
}




version(CustomAA)
{
	import alt.arraymap;
	alias HashTable!(string,Builder)	BuilderMap;
}
else {
	alias Builder[string]	BuilderMap;
}
/** A call backclass can get delegate callbacks on a key, and can also setup a builder class to collect
	structured tags and/or content till its element ends. The same builder instance can be used for multiple tags,
	for example a generic Element tree builder, but only if associated with each element name and end callback.
	To use a builder for all further tags in an element, but without callback, it needs to be 
	set via the call XmlVisitor.setBuilder, and not the keyed callback registration. The init call will not occur. I
	It is assumed the setter configured it already. But the finish method will be called.
	With setBuilder, it becomes immediately active until the end of element it was set in, but does not use a call back.

	Note that using the setBuilder method, the Builder instance takes over the management of XmlReturn parse events.
	Any other callbacks will be subverted, until the element is exited.
	DO NOI to call setBuilder, from inside the Builders methods, unless prepared for exciting debugging sessions.

	The Builder class can be utilized in a smaller way, by passing 
	an instance,  associated with each element name that it is to be used for.
	---
	// This sets a callback for the end tag, and lets the builder instance handle parse events from all the elements children.
	vistor[builder_instance,"elementName"] = (XmlVisitor v, ref XmlReturn ret) {}	
	
	---


	When a builder is activated, by encountering a registered start tag for it, it calls init to initialize the builder, which might its own pushTag.
	When the matching end tag is reached, a callback for the END_TAG is searched for.

	So setting a builder must be done with a callback as well, which is provided in the builder opIndexAssign.
	The call back for the end builder, returns the builder class, as the XmlReturn.node Object.

	There is only one active builder at a time, they cannot be nested.
	Delegates are not called back while a builder is active.
	While a builder is in use, the callback stack of XmlVisitor is not altered. Its up to the builder object,
	to manage a stack if it requires one.

	Can a delegate for XmlResult.TAG_END set without a builder object, but there will be no builder node returned.*/

class XmlCallBack
{
	version (GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}

		this()
		{
			gcStatsSum.inc();
		}

	}

	~this()
	{
		explode(false);
		version (GC_STATS)
		{
			gcStatsSum.dec();
		}
	}

	private {
		ParseDg[XmlKey] dg;
		BuilderMap		builders;
	}
	/// [Builder, "tagname"], for Builder instance be called for everything between starttag, and endtag for "tagname",
	/// and call the ParseDg after the endtag.
	void opIndexAssign(ParseDg pdg, Builder b, string tagkey)
	{
		assert(tagkey.length > 0,"Builder class must be associated with element name");
		dg[XmlKey(tagkey, XmlResult.TAG_END)] = pdg;
		builders[tagkey] = b;
	}
	/// remove [Builder, "tagname"]
	void removeBuilder(string tagkey)
	{
		dg.remove(XmlKey(tagkey, XmlResult.TAG_END));
		builders.remove(tagkey);
	}
	/// [ XmlResult.xxx ] Associates the XmlResult.type with a callback, not to be used for TAG_END,
    void opIndexAssign(ParseDg pdg,  XmlResult rkey)
    {
		assert(rkey != XmlResult.TAG_END && rkey != XmlResult.TAG_START && rkey != XmlResult.TAG_SINGLE);
        dg[XmlKey(null,rkey)] = pdg;
    }
	/// remove for [ XmlResult.xxx ]
    void remove(XmlResult rkey)
    {
		assert(rkey != XmlResult.TAG_END && rkey != XmlResult.TAG_START  && rkey != XmlResult.TAG_SINGLE);
        dg.remove(XmlKey(null,rkey));
    }

	/// Tag event without a builder.  TAG_START, TAG_EMPTY, or TAG_END
	/// [ "tagname", [ XmlResult.xxx ] 
    void opIndexAssign(ParseDg pdg, string tagkey, XmlResult rkey = XmlResult.TAG_START)
    {
        dg[XmlKey(tagkey,rkey)] = pdg;
    }
	/// corresponding removal for  [ "tagname", [ XmlResult.xxx ] ] TAG_START, TAG_EMPTY, or TAG_END
	void remove(string tagkey, XmlResult rkey = XmlResult.TAG_START)
	{
		 dg.remove(XmlKey(tagkey,rkey));
	}

	/// Try to ensure aliased strings, keys and values are all collectible.

	void explode(bool del)
	{
		if (del)
		{
			if (dg.length > 0)
			{
				auto keys = dg.keys();
				foreach(k ; keys)
					dg.remove(k);
				dg = null;
			}
			
			if (builders.length > 0)
			{
				auto bkeys = builders.keys();
				foreach(bkey ; bkeys)
					builders.remove(bkey);
				builders = null;
			}
			delete this;
		}
			
	}

};




private struct ParseLevel
{
    string              tag_;
    XmlCallBack         callbacks_;
	Builder				builder_;
};


/** Intercepts the XmlReturn parse results, and redistributes them to a Builder based Object,
  or callbacks as set by the user with the setCallBacks method.
	XmlVisitor is only a messenger boy. XmlVisitor cannot perform advanced validation, namespace decoding,
	which is some extra work, especially without a standard DOM.
	Attribute decoding is enabled or disabled by attribute-normalize property, set via the IXMLParser.setParameter interface method.
	Default is set to true in XmlVisitor constructor.
*/ 
class XmlVisitor  {
	protected IXMLParser		xp_;
	Array!ParseLevel			parseStack_;
	Builder						builder_;
	bool						externalBuilder_;

	// count of builder element depth, set on starting a builder.
	intptr_t					builderLevel_;
	intptr_t					builderEndLevel_;
	
public:
	/// Experimental and dangerous for garbage collection. No other references must exist.
	version (GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}
	
	void explode(bool del)
	{
		builder_ = null;
		xp_ = null;
		parseStack_.free();
		if (del)
			delete this;
	}

	/// Initialised with a single stack level, to put in callbacks
	this(IXMLParser xp)
	{
		xp_ = xp;
		parseStack_.length = 1;
		version(GC_STATS)
			gcStatsSum.inc();
		// This is a low level handler.
		xp_.setParameter(xmlAttributeNormalize,Variant(true));
	}

	~this()
	{
		explode(false);
		version(GC_STATS)
			gcStatsSum.dec();
	}

	/// Sets at current stack level.  Nothing will happend until parseDocument is called.
	XmlCallBack setCallBacks(XmlCallBack cb)
	{
		parseStack_.last().callbacks_ = cb;
		return cb;
	}
    /// Do a callback controlled parse of document
    void parseDocument()
    {
        XmlReturn   ret;
        // Has to be depth - 1, otherwise premature exit
        intptr_t    startLevel = parseStack_.length;
		//intptr_t	builderLevel = 0;

        while(xp_.parse(ret))
        {
			if (builder_ !is null)
			switch (ret.type)
			{
				case XmlResult.STR_TEXT:
					builder_.text(ret);
					break;
				case XmlResult.TAG_START:
					builderLevel_++;
					builder_.pushTag(ret);
					break;
				case XmlResult.TAG_SINGLE:
					builder_.singleTag(ret);
					break;
				case XmlResult.TAG_END:	
					builderLevel_--;
					if (builderLevel_ == builderEndLevel_)
					{
						// The stack is wrong if externalBuilder_
						//builder_.finish(this);
						if (externalBuilder_)
						{
							externalBuilder_ = false;
							builder_ = null;
							return;
						}
						
						callbackEndTag(ret);
						builder_ = null;
					}
					else {
						builder_.popTag(ret);
					}
					break;
				case XmlResult.STR_CDATA:
					builder_.cdata(ret);
					break;
				case  XmlResult.STR_COMMENT:
					builder_.comment(ret);
					break;
				case XmlResult.STR_PI:
					builder_.processingInstruction(ret);
					break;
				case XmlResult.XML_DEC:
					builder_.xmldec(ret);
					break;
				case XmlResult.RET_NULL:
					break;
				default:
					break;
			}
			else
            //auto preState = state_;
            switch(ret.type)
            {
				case XmlResult.STR_TEXT:
					callbackText(ret);
					break;
				case XmlResult.TAG_START:
					callbackStartTag(ret);
					break;
				case XmlResult.TAG_SINGLE:
					callbackEmptyTag(ret);
					break;
				case XmlResult.TAG_END:
					callbackEndTag(ret);
					if (parseStack_.length < startLevel)
						return;
					break;
				case XmlResult.STR_CDATA:
					callbackCDATA(ret);
					break;
				case  XmlResult.STR_COMMENT:
					callbackComment(ret);
					break;
				case XmlResult.STR_PI:
					callbackPI(ret);
					break;
				case XmlResult.XML_DEC:
					callbackXmlDec(ret);
					break;
				case XmlResult.RET_NULL:
					break;
				default:
					break;
            }
        }
    }
    private void cycleOver(string tag)
    {
    }

    private void processStartTag(bool isEmpty)
    {

    }
    // this routine exits after END_TAG
    void parseElements()
    {
    }

    void callbackPI(ref XmlReturn ret)
    {
        auto level = parseStack_.last();
        auto callbacks = level.callbacks_;
        if (callbacks !is null)
        {
            auto dgpi = callbacks.dg.get(XmlPIKey, null);
            if (dgpi !is null)
            {
                dgpi(ret);
            }
        }
    }
    void callbackEndTag(ref XmlReturn ret)
    {
        parseStack_.popBack();
		auto level = parseStack_.back();
        auto callbacks = level.callbacks_;
        if (callbacks !is null)
        {
            auto onEndTag = callbacks.dg.get(XmlKey(ret.scratch,XmlResult.TAG_END),null);

            if (onEndTag !is null)
            {
				ret.node = builder_;
                onEndTag(ret);
				ret.node = null;
            }
        }
    }

	@property Builder builder()
	{
		return builder_;
	}
	/** Maybe done before first call to parseDocument, or after an end tag callback
	    The stack is handled differently
	*/

	void setBuilder(Builder bob)
	{
		builder_ = bob;
		if (bob !is null)
		{
			builderLevel_ = parseStack_.length;
			builderEndLevel_ = builderLevel_;
			externalBuilder_ = true;
		}
	}
    void callbackXmlDec(ref XmlReturn ret)
    {
        auto level = parseStack_.back();
        auto callbacks = level.callbacks_;
        if (callbacks !is null)
        {
			auto dg = callbacks.dg.get(XmlDecKey, null);
            if (dg !is null)
				dg( ret);
		}
    }
    void callbackEmptyTag(ref XmlReturn ret)
    {
		auto level = parseStack_.back();
		auto callbacks = level.callbacks_;
		if (callbacks !is null)
		{
			XmlKey key = XmlKey(ret.scratch, XmlResult.TAG_END);
			auto endCall = callbacks.dg.get(key,null);
			if (endCall !is null)
			{
				// a matching bob the Builder object must exist!
				auto bob = callbacks.builders.get(ret.scratch,null);
				if (bob !is null)
				{
					bob.init(ret);
					//bob.finish(this);
					ret.node = bob;
				}
				// There is no content, so just call end
				endCall( ret);
				ret.node = null;
				return;
			}
			key.type_ = XmlResult.TAG_START;
			auto cb = callbacks.dg.get(key,null);
			if (cb != null)
			{
				cb(ret);
			}
		}
	}
    /// Will start element content
    void callbackStartTag(ref XmlReturn ret)
    {
        auto level = parseStack_.back();
        auto callbacks = level.callbacks_;
		parseStack_.put(ParseLevel(ret.scratch,null));

        if (callbacks !is null)
        {
			auto bob = callbacks.builders.get(ret.scratch,null);
			if (bob !is null)
			{
				builder_ = bob;
				builderLevel_ = parseStack_.length;
				builderEndLevel_ = builderLevel_ - 1; // because startTag did a push already
				bob.init(ret);
				return;
			}

            auto cb = callbacks.dg.get(XmlKey(ret.scratch,XmlResult.TAG_START),null);
            if (cb != null)
            {
                cb(ret);
            }
        }
    }

    void callbackCDATA(ref XmlReturn ret)
    {
		auto callbacks = parseStack_.last().callbacks_;
        if (callbacks !is null)
        {
            auto dg = callbacks.dg.get(XmlCDATAKey,null);
            if (dg !is null)
            {
                dg(ret);
            }
        }
    }
    void callbackText(ref XmlReturn ret)
    {
        auto callbacks = parseStack_.last().callbacks_;
        if (callbacks !is null)
        {
            auto dg = callbacks.dg.get(XmlTextKey,null);
            if (dg !is null)
                dg(ret);
        }
    }
    void callbackComment(ref XmlReturn ret)
    {
		auto callbacks = parseStack_.last().callbacks_;
        if (callbacks !is null)
        {
            auto dg = callbacks.dg.get(XmlCommentKey,null);
            if (dg !is null)
                dg(ret);
        }
    }
}

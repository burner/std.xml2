/**

Effort to make an XML parser that slices off data used to build a DOM, from original source string
as much as possible.

Avoids overhead of allocating memory for strings, so has faster execution time.
This is best ideally to already canonical normalized XML.

Note validate property needs be set to true, to handle standard character entities in content or attributes.
The charEntityMap can be also setup by calling the IXMLParser interface setEntityValue.
Otherwise its do it yourself character entity handling.

*/

module xmlp.xmlp.sliceparse;

import xmlp.xmlp.xmlchar;
import xmlp.xmlp.dtdtype;
import xmlp.xmlp.subparse;
import alt.zstring;
import xmlp.xmlp.error;
import std.utf;
import std.string;
import std.conv;
import xmlp.xmlp.parseitem;
import xmlp.xmlp.entitydata;
import std.variant;

version(CustomAA)
{
	import alt.arraymap;
}
version=TagStack;// Check tag nesting match
version=speedBump;// for attributeNormalize optimization
/*
void appendAttributes(ref AttributeMap amap, string[] names, string[] values)
{
    for(size_t ix = 0 ; ix < names.length; ix++)
    {
        amap.put(AttributeMap.BlockRec(names[ix], values[ix]));
    }

}
*/
/**
	Maybe a context class would have been better.
*/

private struct SavedContext
{
    dchar				front_;
    size_t				frontIX;
    size_t				nextIX;
    bool				empty_;
    double				docVersion_;
    string				source_;
    int					markupDepth;
    int					elementDepth;
    int					squareDepth;
    int					parenDepth;
    EntityData			entity;
    bool				scopePop;
}

/// ensure Context state pops when leaving scope
struct contextPopper
{
    private XmlStringParser fp_;


    /// Make a new context
    this(XmlStringParser fp, string data)
    {
        fp_ = fp;
        fp_.pushContext(data,true,null);
    }
    /// Ensure existing context is popped on scope exit
    this(XmlStringParser fp)
    {
        fp_ = fp;
    }

    /// pop on scope exit
    ~this()
    {
        fp_.popContext();
    }
}

/** The simpler input range string source, for working on strings. No putting back.
	Will not even track position or lines

*/

class StringSource
{
    string			source_;
    uintptr_t	    srcIX_;
    uintptr_t		nextIX_;
    dchar			front;
    bool			empty;

	// Ensure set and restore with NoneEmptyState, because empty will only happen once.
	struct NoneEmptyState {
		uintptr_t NES_srcIX_;
		uintptr_t NES_nextIX_;
		dchar	  NES_front;
	}
 	/** string of the current context,
		starting with position of front
		*/
	string	source() const
	{
		return source_[srcIX_ .. $];
	}

	uintptr_t frontIndex() const
	{
		return srcIX_;
	}

	package final void setSingleCharPos(uintptr_t srcpos)
	{
		// make it as if a single 8 bit character at srcpos, has just been made front by popFront
		// effecting a pushBack
		srcIX_ = srcpos;
		nextIX_ = srcpos + 1;
		front = source_[srcpos];
	}

	package final void setState(ref NoneEmptyState nes)
	{
		with (nes) {
			srcIX_ = NES_srcIX_;
			nextIX_ = NES_nextIX_;
			front = NES_front;
		}
	}
	package final void getState(ref NoneEmptyState nes)
	{
		with (nes)
		{
			NES_srcIX_ = srcIX_;
			NES_nextIX_ = nextIX_;
			NES_front = front;
		}
	}
    void pumpStart()
    {
        if (!empty)
            return;
        if (srcIX_ < source_.length)
        {
            nextIX_ = srcIX_;
            front = decode(source_,nextIX_);
            empty = false;
        }
    }
    final popFront()
    {
        srcIX_ = nextIX_;
        if (nextIX_ < source_.length)
        {
            front = decode(source_,nextIX_);
        }
        else
            empty = true;
    }
    final uint munchSpace()
    {
        int   count = 0;
        while(!empty)
        {
            switch(front)
            {
            case 0x20:
            case 0x0A:
            case 0x09:
            case 0x0D: // may be introduced as character reference
                count++;
                popFront();
                break;
            default:
                return count;
            }
        }
        return 0;
    }
    final bool matchInput(dchar val)
    {
        if (!empty && front == val)
        {
            popFront();
            return true;
        }
        return false;
    }


    final bool matchInput(dstring match)
    {
        if (empty)
            return false;
        size_t lastmatch = 0; // track number of matched
        size_t mlen = match.length;

		NoneEmptyState nes;
		getState(nes);

        for( ; lastmatch < mlen; lastmatch++)
        {
            if (empty)
                break;
            if (front != match[lastmatch])
                break;
            popFront();
        }
        if (lastmatch == 0)
            return false;
        else if (lastmatch == mlen)
            return true;
        else
        {
			setState(nes);
            empty = false;
            return false;
        }
    }

}


/** Fast parser based on StringSource, implements IXMLParser.
	Not expected to be used with Dtd validation as yet.
*/
class XmlStringParser : StringSource, IXMLParser
{
    enum PState
    {
        P_PROLOG,
        P_INT_DTD,
        P_TAG,
        P_ENDTAG,
        P_DATA,
        P_PROC_INST,
		P_BANG,
        //P_COMMENT,
       // P_CDATA,
        P_EPILOG,
        P_END
    }

    PState			state_;
    ErrorStack		estk_;



    bool			scopePop_;
    int				itemCount;
    int				markupDepth_;
    int				elementDepth_;
    int				stackElementDepth_;
    int				squareDepth_;
    int				parenDepth_;
    EntityData		entity_;
    SavedContext[]	contextStack_;
    XmlStringParser	master;
    CharTestFn		isNameStartFn;
    CharTestFn		isNameCharFn;
    double			XMLVersion;
    uint			maxEdition;
    bool			validate_;

    bool			hasDeclaration;
    bool			inDTD_;
    bool			namespaceAware;
    bool			isStandalone_;
    bool			isEntity;
    bool			hasXmlVersion;
    bool			hasStandalone;
    bool			hasEncoding;
    bool			normalizeAttributes;

    Array!char	content_;
    version(speedBump)
        Array!char	normValue_;
    Array!dchar	endCheck_;

    StdEntityMap		charEntity;
    ProcessingInstructionDg		onProcessingInstruction_;
    string[]			searchPaths_;
    IDValidate			idValidate_;
    PrepareThrowDg		prepareExDg;
    ReportInvalidDg		reportInvalid_;

    version(TagStack)  Array!string  tagStack_;

    /// construct
    this()
    {
        estk_ = new ErrorStack();
        empty = true;
        validate = true;
        isNameStartFn = &isNameStartChar10;
        isNameCharFn = &isNameChar10;

		version(TagStack)
			tagStack_.reserve(16);
        // cannot pumpStart yet
    }
    /// construct
    this (string sourceText)
    {
        this();
        source_ = sourceText;
        state_ = PState.P_PROLOG;
        pumpStart();

    }

	~this()
	{

		version(CustomAA)
		{
			charEntity.clear();
		}
	}

    /// called after setting source text
    void initParse()
    {
        pumpStart();
    }

    bool inParamEntity() const { return false; }
    bool inGeneralEntity() const { return false; }

    override void reportInvalid()
    {

    }

    /// IXMLParser method
    @property final ErrorStack getErrorStack()
    {
        return estk_;
    }

    /// conform with IXMLParser.  No effect yet
    override void setParameter(string name, Variant n)
    {	
		switch(name)
		{
		case xmlAttributeNormalize:
			normalizeAttributes = n.get!bool;
			break;
		default:
			break;
		}
	}
    bool nameSpaces()
    {
        return namespaceAware;
    }

    /// IXMLParser method, may not actually be used
    @property bool isParamEntity()
    {
        return (entity_ !is null) && (entity_.etype_ == EntityType.Parameter);
    }

    ///  IXMLParser method, may not actually be used
    @property bool isGeneralEntity()
    {
        return (entity_ !is null) && (entity_.etype_ == EntityType.General);
    }

    ///   IXMLParser method, may not actually be used
    @property string entityName()
    {
        return entity_ !is null ? entity_.name_ : null;
    }

    ///   IXMLParser method, may not actually be used
    @property EntityData entityContext()
    {
        return entity_;
    }

    /// property
    @property void entityContext(EntityData val)
    {
        entity_ = val;
    }
    /// property
    @property bool isInternalContext()
    {
        return (entity_ is null) || (entity_.isInternal_);
    }

    /// property
    @property bool isStandalone() const
    {
        return isStandalone_;
    }
    /// property
    @property bool validate() const
    {
        return validate_;
    }
    @property void validate(bool doValidate)
    {
        validate_ = doValidate;
        normalizeAttributes = doValidate;
        if (charEntity.length == 0)
            charEntity = stdCharEntityMap();
    }

    string getEntityName()
    {
        return entityName();
    }
    /// property
    @property bool namespaces() const
    {
        return namespaceAware;
    }
    @property void namespaces(bool doNamespaces)
    {
        namespaceAware = doNamespaces;
    }
    /// property
    @property double xmlVersion()
    {
        return XMLVersion;
    }

    /// paths
    override void systemPaths(string[] paths)
    {
        searchPaths_ = paths;
    }
    /// paths
    override string[] systemPaths()
    {
        return searchPaths_;
    }
    ///   IXMLParser method, may not actually do anything
    void attributeTextReplace(string src, ref string value, uint callct = 0)
    {
        value = src;
    }
    ///   method, will complain with exception
    public bool doDocType(ref XmlReturn ret)
    {
        // do limited internal ENTITY, NOTATION?
        throwNotWellFormed("DOCTYPE not supported");
        return false;
    }
    ///   method,may not actually do anything
    IDValidate idSet()
    {
        return idValidate_;
    }

    @property bool inDTD()
    {
        return inDTD_;
    }
    ///   method,may not actually be useful
    void createIdSet()
    {
        idValidate_ = new IDValidate();
    }
    ///   method,may not actually do anything
    void setReportInvalidDg(ReportInvalidDg dg)
    {
        reportInvalid_ = dg;
    }
    ReportInvalidDg getReportInvalidDg()
    {
        return reportInvalid_;
    }

    /// IXMLParser
    void pushContext(string s, bool scoped, EntityData ed)
    {
        SavedContext ctx;
        readContext(ctx);
        auto slen = contextStack_.length;

        if (slen == 0)
            stackElementDepth_ = elementDepth_;
        else
            stackElementDepth_ += elementDepth_;
        contextStack_ ~= ctx;
        initContext(s, scoped, ed);
        pumpStart();
    }

    /// Location is string offset
    void getLocation(ref SourceRef sref)
    {
        sref.charsOffset = srcIX_;
        sref.lineNumber = -1;
        sref.colNumber = -1;
    }

    /// delegate for exception handling
    void setPrepareThrowDg (PrepareThrowDg dg)
    {
        prepareExDg = dg;
    }
    PrepareThrowDg getPrepareThrowDg ()
    {
        return prepareExDg;
    }
    /// IXMLInterface
    public ParseError prepareThrow(ParseError x)
    {
        if (prepareExDg !is null)
            return prepareExDg(x);
        else
            return x;
    }

    static string badCharMsg(dchar c)
    {
        return format("bad character 0x%x [%s]\n", c, c);
    }

    void ThrowEmpty()
    {
        throwNotWellFormed(ParseErrorCode.UNEXPECTED_END);
    }
    /// IXMLInterface
    void throwParseError(string msg)
    {
        Exception ex = prepareThrow(new ParseError(msg, ParseError.error));
        if (ex !is null)
            throw ex;
    }

    /// IXMLInterface
    void throwErrorCode(ParseErrorCode code)
    {
        Exception ex = prepareThrow(new ParseError(code));
        if (ex !is null)
            throw ex;
    }

    /// IXMLInterface
    void throwNotWellFormed(ParseErrorCode code)
    {
        Exception ex = prepareThrow(new ParseError(code));
        if (ex !is null)
            throw ex;
    }
    /// set delegate call back Processing Instructions

	void setProcessingInstructionDg(ProcessingInstructionDg dg)
    {
        onProcessingInstruction_ = dg;
    }

    void throwNotWellFormed(string s)
    {
        Exception ex = prepareThrow(new ParseError(s));
        if (ex !is null)
            throw ex;
    }

    Exception getNotWellFormed(string s)
    {
        return prepareThrow(new ParseError(s));
    }
    Exception getParseError(string s)
    {
        return prepareThrow(new ParseError(s, ParseError.error));
    }
    Exception getUnexpectedEnd()
    {
        return  prepareThrow(new ParseError("Unexpected end"));
    }

    final bool getAttributeValue(ref string app)
    {
        munchSpace();
        dchar test;
        if (empty || (front != '='))
            throwNotWellFormed(ParseErrorCode.EXPECTED_ATTRIBUTE);
        popFront();
        munchSpace();
        if (!unquoteValue(app))
            throwNotWellFormed(ParseErrorCode.EXPECTED_ATTRIBUTE);
        return true;
    }

    final bool unquoteValue(ref string app)
    {
        dchar enquote = (empty ? 0x00 : front);
        if ((enquote != '\'') && (enquote != '\"'))
        {
            throwNotWellFormed(ParseErrorCode.MISSING_QUOTE);
            return false;
        }
        popFront();
        size_t initPos = srcIX_;
        while(!empty)
        {
            if (front == enquote)
            {
                app = source_[initPos..srcIX_];
                popFront();
                return true;
            }
            else
            {
                popFront();
            }
        }
        throwNotWellFormed(ParseErrorCode.MISSING_QUOTE);
        return false;
    }

    void readContext(ref SavedContext ctx)
    {
        with(ctx)
        {

			source_ = this.source_;
			front_ = this.front;
            empty_ = this.empty;
			frontIX = this.srcIX_;
            nextIX = this.nextIX_;
			docVersion_ = this.XMLVersion;
            markupDepth = this.markupDepth_;
            elementDepth = this.elementDepth_;
            squareDepth = this.squareDepth_;
            parenDepth = this.parenDepth_;
            entity = this.entity_;
            scopePop = this.scopePop_;
        }
    }

    void writeContext(ref SavedContext ctx)
    {
        with(ctx)
        {
            this.source_ = source_;
            this.front = front_;
            this.empty = empty_;
            this.srcIX_ = frontIX;
            this.nextIX_ = nextIX;
            this.XMLVersion = docVersion_;
            this.markupDepth_ = markupDepth;
            this.elementDepth_ = elementDepth;
            this.squareDepth_ = squareDepth;
            this.parenDepth_ = parenDepth;
            this.entity_ = entity;
            this.scopePop_ = scopePop;

        }
    }
    final bool getXmlName(ref string tag)
    {
        if (empty)
            return false;
        if ( !(isNameStartFn(front) || isNameStartFifthEdition(front)) )
            return false;
        size_t initPos = srcIX_;

        popFront();
        while (!empty)
        {
            if (isNameCharFn(front) || isNameCharFifthEdition(front))
            {
                popFront();
            }
            else
                break;
        }
        tag = source_[initPos..srcIX_];
        return true;
    }
    bool isNameStartFifthEdition(dchar test)
    {
        if (XMLVersion == 1.0 && maxEdition >= 5)
        {
            if (!isNameStartChar11(test))
                return false;

            if (validate_)
            {
                estk_.pushMsg("Name start character only specified by XML 1.0 fifth edition",ParseError.invalid);
                reportInvalid();
            }
            return true;
        }
        return false;
    }
    bool isNameCharFifthEdition(dchar test)
    {
        if (XMLVersion == 1.0 && maxEdition >= 5)
        {
            if (!isNameChar11(test))
                return false;

            if (validate_)
            {
                estk_.pushMsg("Name character only specified by XML 1.0 fifth edition",ParseError.invalid);
                reportInvalid();
            }
            return true;
        }
        return false;
    }
    /// IXMLParser
    void popContext()
    {
        auto slen = contextStack_.length;
        if (slen > 0)
        {
            slen--;
            writeContext(contextStack_[slen]);
            contextStack_.length = slen;
            if (slen > 0)
                stackElementDepth_ -= elementDepth_;
            else
                stackElementDepth_ = 0;
        }
    }
    void initContext(string s, bool scoped, EntityData ed = null)
    {
        front = 0;
        empty = true;
        markupDepth_ = 0;
        elementDepth_ = 0;
        squareDepth_ = 0;
        parenDepth_ = 0;
        entity_ = ed;
        source_ = s;
        srcIX_ = 0;
        empty = true;
        scopePop_ = scoped;
    }


    Exception getBadCharError(dchar c, uint severity = ParseError.fatal)
    {
        return prepareThrow(new ParseError(badCharMsg(c),severity));
    }


    /// got a '[', check the rest
    final bool isCDataEnd()
    {
        if (empty || front != ']')
            return false;

		NoneEmptyState nes;
		getState(nes);

        void restore()
        {
			setState(nes);
            empty = false;
        }

        squareDepth_--;
        popFront();
        if (empty || front != ']')
        {
            restore();
            squareDepth_++;
            return false;
        }
        squareDepth_--;
        popFront();
        if (empty || front != '>')
        {
            restore();
            squareDepth_ += 2;
            return false;
        }
        markupDepth_--;
        popFront();
        return true;
    }
    final bool doCDATAContent(ref XmlReturn ret)
    {
        state_ = PState.P_DATA;
        size_t srcPos = srcIX_;
        while(!empty)
        {
            if ((front == ']') && isCDataEnd())
            {
                ret.scratch = source_[srcPos .. srcIX_-3];
                ret.type = XmlResult.STR_CDATA;
                itemCount++;
                return true;
            }
            else
            {
                popFront();
            }
        }
        ThrowEmpty();
        return false;
    }

    bool parse(ref XmlReturn ret)
    {
        switch(state_)
        {
        case PState.P_TAG:
            return doStartTag(ret);
            /+


            +/
        case PState.P_DATA:
            return doContent(ret);

        case PState.P_ENDTAG:
            return doEndTag(ret);

		case PState.P_BANG:
			return doBang(ret);

		/*
        case PState.P_CDATA:
            return doCDATAContent(ret);

        case PState.P_COMMENT:
            return doCommentContent(ret);
		*/

        case PState.P_PROC_INST:
            return doProcessingInstruction(ret);

        case PState.P_PROLOG:
            return doProlog(ret);

        case PState.P_EPILOG:
            return doEpilog(ret);

        case PState.P_END:
        default:
            break;

        }
        return false;
    }

    private final bool isCommentEnd()
    {
        if (empty || front != '-')
            return false;
        popFront();
        if (empty || front != '>')
            throwNotWellFormed("Comment must not contain --");
        markupDepth_--;
        popFront();
        return true;
    }
    protected int totalElementDepth()
    {
        return elementDepth_ + stackElementDepth_;
    }
    protected int elementDepth()
    {
        return elementDepth_;
    }
    final void parseComment(ref string content)
    {
        dchar  test  = 0;
        auto initPos = srcIX_;
        while(!empty)
        {
            if (front=='-')
            {
                popFront();
                if (isCommentEnd())
                {
                    content = source_[initPos..srcIX_-3];
                    return;
                }

                continue;
            }
            popFront();
			
        }
        throwNotWellFormed("Unterminated comment");
    }
	
	/// allow user to monitor state
	@property PState state() const
	{
		return state_;
	}
    final bool doCommentContent(ref XmlReturn ret)
    {
        if ((state_ != PState.P_PROLOG) && (state_ != PState.P_EPILOG))
            state_ = PState.P_DATA;

        parseComment(ret.scratch);
        ret.type = XmlResult.STR_COMMENT;
        itemCount++;
        return true;
    }

    void throwUnknownEntity(string ename)
    {
        string s = format("Unknown entity %s", ename);
        uint level = (isParamEntity) ? ParseError.error : ParseError.fatal;

        throw prepareThrow(new ParseError(s, level));
    }

    bool decodeEntityReference(string ename, bool isAttribute)
    {
        return false;
        //throw getUnknownEntity(ename);
    }


    bool doProlog(ref XmlReturn item)
    {
        dchar testchar;
        string  content;
        int spaceCt;
        while(!empty)
        {
            spaceCt = munchSpace();

            if (empty)
                break;

            if (front == '<')
            {
                markupDepth_++;
                //frontFilterOff();

                popFront();
                switch(front)
                {
                case '?':
					setSingleCharPos(srcIX_-1);
					markupDepth_--;
                    return doProcessingInstruction(item, spaceCt);
                case '!':
                    popFront();
                    if (empty)
                        ThrowEmpty();
                    if (matchInput(DOCTYPE_d))
                    {
                        return doDocType(item);
                    }
                    else if (matchInput(DASH2_d))
                    {
                        return doCommentContent(item);
                    }
                    else
                        throwNotWellFormed("Illegal in prolog");
                    goto default;
                default:
                    if (isNameStartFn(front) || isNameStartFifthEdition(front))
                    {
                        if (!hasDeclaration)
                        {
                            if (validate_)
                            {
                                estk_.pushMsg("No xml declaration",ParseError.invalid);
                            }
                        }
						state_ = PState.P_TAG;
						setSingleCharPos(srcIX_-1);
						markupDepth_--;
                        return doStartTag(item);
                    }
                    else
                        throw getBadCharError(testchar);
                } // end switch


            } // end peek
            else
            {
                throwNotWellFormed("expect xml markup");
            }
            // else?
        } // end while
        throwNotWellFormed("bad xml");
        assert(0);
    }
/// Very testy function.  Attributes are not acted on until the whole declaration is parsed!
    bool doXmlDeclaration(ref XmlReturn ret)
    {
        double xml_value = 1.0;

        //state_ = XML_DECLARATION;
        int spaceCt =  munchSpace();
        size_t atcount = 0;
        isStandalone_ = false; // if has an xml declaration, assume false as default
        string atname;
        string atvalue;

        void xmlVersionFirst(bool force=false)
        {
            if (!isEntity || force)
                estk_.pushMsg("xml version must be first",XML_ERROR_FATAL);
        }

        void xmlDuplicate()
        {
            estk_.pushMsg(text("duplicate ", atname),XML_ERROR_FATAL);
        }
        void xmlStandaloneLast()
        {
            estk_.pushMsg("xml standalone must be last",XML_ERROR_FATAL);
        }

		ret.attr.clear();

        // get the values before processing

        while(!matchInput("?>"))
        {
            if (!getXmlName(atname))
            {
                //throwNotWellFormed("declaration attribute expected");
                // got a strange character?
                if (empty)
                    ThrowEmpty();
                dchar badChar = front;
                //Extreme focus on XML declaration conformance errors.
                switch(badChar)
                {
                case '>':
                case '<':
                    throwNotWellFormed("expected ?>");
                    break;
                case '\'':
                case '\"':
                    throwNotWellFormed("expected attribute name");
                    break;
                case 0x85:
                case 0x2028:
                    if (xml_value == 1.1)
                        throw getParseError(format("%x illegal in declaration", badChar));
                    goto default;
                default:
                    throwNotWellFormed(badCharMsg( badChar));
                }
            }


            if  (!spaceCt)
                throwNotWellFormed("missing spaces");

            if (!getAttributeValue(atvalue) || atvalue.length==0)
                throwNotWellFormed("declaration value expected");

            atcount += 1;
			ret.attr.put(AttributeMap.BlockRec(atname,atvalue));

            switch(atname)
            {
            case "version":
                if (hasXmlVersion)
                {
                    xmlDuplicate();
                    break;
                }
                if (hasStandalone || hasEncoding)
                    xmlVersionFirst(true);
                hasXmlVersion = true;
                xml_value = doXmlVersion(atvalue);
                break;
            case "encoding":
                if (!hasXmlVersion)
                    xmlVersionFirst();
                if (hasStandalone)
                    xmlStandaloneLast();
                if (hasEncoding)
                {
                    xmlDuplicate();
                    break;
                }
                hasEncoding = true;
                break;
            case "standalone":
                if (isEntity)
                    throwNotWellFormed("standalone illegal in external entity");
                if (!hasXmlVersion)
                    xmlVersionFirst();
                if (hasStandalone)
                {
                    xmlDuplicate();
                    break;
                }
                hasStandalone = true;
                break;
            default:
                throwNotWellFormed(text("unknown declaration attribute ", atname));
                break;
            }
            spaceCt = munchSpace();
        }
        if (hasXmlVersion)
            setXmlVersion(xml_value);

        markupDepth_--;
        if (isEntity && !hasEncoding)
            throwNotWellFormed("Optional entity text declaration must have encoding=");
        checkErrorStatus();
        ret.type = XmlResult.XML_DEC;
        ret.scratch = null;

		if (hasEncoding)
			setXmlEncoding(ret.attr["encoding"]);
		if (hasStandalone)
			setXmlStandalone(ret.attr["standalone"]);

        itemCount++;
        return true;
    }
    bool doProcessingInstruction(ref XmlReturn ret, uint spaceCt = 0)
    {
		setSingleCharPos(srcIX_ + 2);
		markupDepth_++;
        string target;
        if (!getXmlName(target))
            throwNotWellFormed("Bad processing instruction name");
        if (namespaceAware && (indexOf(target,':') >= 0))
            throwNotWellFormed(text(": in process instruction name ",target," for namespace aware parse"));

        if (target == "xml")
        {
            if (inDTD)
                throwNotWellFormed("Xml declaration may not be in DTD");
            if (state_ != PState.P_PROLOG || (spaceCt > 0) || (itemCount > 0))
                throwNotWellFormed("xml declaration should be first");
            if (!hasDeclaration)
            {
                hasDeclaration = true;
                try
                {
                    ret.scratch = target;
                    bool result = doXmlDeclaration(ret);
					if (result)
						munchSpace();
					return result;
                }
                catch (ParseError ex)
                {
                    throw prepareThrow(ex);
                }
            }
            else
                throwNotWellFormed("Duplicate xml declaration");
        }
        if ((state_ != PState.P_PROLOG)&&(state_ != PState.P_EPILOG))
            state_ = PState.P_DATA;

        auto lcase = target.toLower();

        if (lcase == "xml")
        {
            throwNotWellFormed(text(target," is invalid name"));
        }

        string value;
        getPIData(value);
		
        ret.type = XmlResult.STR_PI;
        ret.scratch = target; // in both places, why not?
		ret.attr.put(AttributeMap.BlockRec(target,value));

        itemCount++;
		if (state_ == PState.P_PROLOG)
			munchSpace();
        return true;
    }
    final void checkEndElement()
    {
        int depth =  totalElementDepth();
        if (depth < 0)
            throwNotWellFormed(ParseErrorCode.ELEMENT_NESTING);
        else if (depth == 0)
            state_ = PState.P_EPILOG;
        if (elementDepth_ < 0)
            throwNotWellFormed(ParseErrorCode.ELEMENT_NESTING);
    }

    final void getPIData(ref string app)
    {
        dchar  test  = 0;

        bool	hasContent = false;
        bool	hasSpace = false;
        size_t	initPos;

        while(!empty)
        {
            test = front;
            popFront();
            if (test=='?')
            {
                if (!empty && front=='>')
                {
                    markupDepth_--;
                    popFront();
                    if (hasContent)
                        app = source_[initPos..srcIX_-2];
                    else
                        app = null;
                    return;
                }
            }
            if (!hasContent)
            {
                if (isSpace(test))
                    hasSpace = true;
                else
                {
                    hasContent = true;
                    initPos = srcIX_;
                    if (!hasSpace)
                        throwNotWellFormed("space required after target name");
                }
            }
        }
    }
    final bool doStartTag(ref XmlReturn r)
    {
        state_ = PState.P_DATA;
		
		if (!empty && front=='<')
		{
			markupDepth_++;
			popFront();
		}
		
        if (!getXmlName(r.scratch))
            throw getParseError("Expected tag name");
        elementDepth_++;
	

		r.attr.clear();

        string atname, atvalue;

        int attSpaceCt = 0;
        bool isClosed = false;

        void checkAttributes()
        {
			if (r.attr.length > 1)
			{
				r.attr.sort();
				auto dupix = r.attr.getDuplicateIndex();
				if (dupix >= 0)
				{
					throwNotWellFormed(ParseErrorCode.DUPLICATE_ATTRIBUTE);
				}
			}
        }


        while (true)
        {
            attSpaceCt = munchSpace();

            if (empty)
                throwNotWellFormed(ParseErrorCode.UNEXPECTED_END);

            switch(front)
            {
            case '>': // no attributes, but possible inner content
                markupDepth_--;
                popFront();
                checkAttributes();

                if (empty)
                    ThrowEmpty();
                /* Check for immediate following end tag, which means TAG_EMPTY */
                r.type = XmlResult.TAG_START;
                if (front == '<')
                {
					NoneEmptyState nes;
					getState(nes);
                    markupDepth_++;

					// regression ticket 7: popping front here, because want to check if next character is a / using a strict input range
					// to check the dchar
                    popFront();
                    if (empty)
                        ThrowEmpty();
                    if (front == '/')
                    {
                        // by strict rules of XML, must be the end tag of preceding start tag.
                        popFront();
                        if (empty)
                            ThrowEmpty();
                        string endTag;
                        if (!getXmlName(endTag) || (endTag != r.scratch))
                        {
                            throwNotWellFormed(ParseErrorCode.ELEMENT_NESTING);
                        }
                        if (empty || (front != '>'))
                        {
                            throwNotWellFormed(ParseErrorCode.MISSING_END_BRACKET);
                        }
                        markupDepth_--;
                        elementDepth_--; // cancel earlier increment
                        popFront();
                        r.type = XmlResult.TAG_SINGLE; // signal no content
                        checkEndElement();
						itemCount++;
						return true;
                    }
                    else
                    {
                        // ticket 7: But if its not a /, want to put the '<' , because its surely a start tag
						// so the price of having an empty tag check, seems to be extra work done for immediate inner tag start
						// put it back as a dchar.  But do not have pushFront here. Slicing and using restored index.
						// Formalize with a NoneEmptyState struct

                        markupDepth_--;
						setState(nes);

                    }
                }
                itemCount++;
				tagStack_.push(r.scratch);
                return true;
            case '/':
                popFront();
                if (empty)
                    ThrowEmpty();
                if (front != '>')
                    throwNotWellFormed(ParseErrorCode.TAG_FORMAT);
                markupDepth_--;
                elementDepth_--;
                popFront();
                checkAttributes();
                r.type = XmlResult.TAG_SINGLE;
                checkEndElement();
                itemCount++;
                return true;

            default:
                if (attSpaceCt == 0)
                {
                    throwNotWellFormed(ParseErrorCode.MISSING_SPACE);
                }
                if (!getXmlName(atname))
                {
                    estk_.pushMsg(getErrorCodeMsg(ParseErrorCode.EXPECTED_ATTRIBUTE),ParseError.invalid);
                    throw getBadCharError(front);
                }

                if (attSpaceCt == 0)
                    throwNotWellFormed(ParseErrorCode.MISSING_SPACE);

                getAttributeValue(atvalue);
                if (normalizeAttributes)
                    atvalue = this.attributeNormalize(atvalue);
				r.attr.put(AttributeMap.BlockRec(atname,atvalue));		
                break;
            }
        }
        assert(0);
    }
    /// already got a '</' and put it back expecting a Name>
    final bool doEndTag(ref XmlReturn ret)
    {
        state_ = PState.P_DATA;
        dchar  test;
		setSingleCharPos(srcIX_+2);
		markupDepth_++;
        if (getXmlName(ret.scratch))
        {
            // has to be end
            munchSpace();
            if (empty || front != '>')
                throwNotWellFormed(ParseErrorCode.MISSING_END_BRACKET);
            markupDepth_--;
            elementDepth_--;
            version(TagStack)
            {
                if (tagStack_.length > 0)
                {
                    string tagCheck = tagStack_.back();
                    tagStack_.popBack();
                    if (tagCheck != ret.scratch)
                        throwNotWellFormed(ParseErrorCode.ELEMENT_NESTING);
                }
                else // Not really expecting to throw here, unless code error
                    throwNotWellFormed(ParseErrorCode.ELEMENT_NESTING);
            }
            popFront();
            checkEndElement();
            ret.type = XmlResult.TAG_END;
            itemCount++;
            return true;
        }
        throwNotWellFormed("end tag expected");
        assert(0);
    }

    double doXmlVersion(string xmlversion)
    {
        auto pp = contextPopper(this,xmlversion);
        Array!char	scratch;
        NumberClass nc = parseNumber(this, scratch);

        //auto vstr = scratch_.toArray;
        if (nc != NumberClass.NUM_REAL)
            throwNotWellFormed(text("xml version weird ",xmlversion));
        if (scratch.length < xmlversion.length)
            throwNotWellFormed("additional text in xml version");
        return  to!double(scratch.toArray);
    }
    void setXmlVersion(double value)
    {
        if ((value != 1.0) && (value != 1.1))
        {
            uint major = cast(uint) value;
            if (major != 1 || maxEdition < 5)
                throw getParseError(text("XML version not supported ",value));
        }
        XMLVersion = value;
    }
    void setXmlEncoding(string encoding)
    {
        bool encodingOK = (encoding.length > 0) && isAlphabetChar(encoding[0]);
        if (encodingOK)
        {
            encodingOK = isAsciiName!(string)(encoding);
        }
        if (!encodingOK)
        {
            throwNotWellFormed(text("Bad encoding name: ", encoding));
        }
        // prepare to fail low level
        try
        {
            //dataFiller_.setEncoding(encoding);
        }
        catch (ParseError ex)
        {
            // defer
            switch(ex.severity)
            {
            case ParseError.invalid:
                // convert to report and carry on
                if (validate_)
                {
                    estk_.pushMsg(ex.toString(),XML_ERROR_INVALID);
                }
                break; // ignore
            case ParseError.error:
                estk_.pushMsg(ex.toString(),XML_ERROR_ERROR);
                throw prepareThrow(ex);

            case ParseError.fatal:
            default:
                estk_.pushMsg(ex.toString(),XML_ERROR_FATAL);
                throw prepareThrow(ex);

            }
        }
        //dataFiller_.setBufferSize(SRC_BUF_SIZE);
    }
    void setXmlStandalone(const(char)[] standalone)
    {
        if (standalone == "yes")
            isStandalone_ = true;
        else if (standalone == "no")
            isStandalone_ = false;
        else
            throwNotWellFormed(text("Bad standalone value: ",standalone));
    }
    protected void checkErrorStatus()
    {
        switch(estk_.errorStatus)
        {
        case XML_ERROR_FATAL:
            throwNotWellFormed("fatal errors");
            break;
        case XML_ERROR_ERROR:
            throw getParseError("errors");
        case XML_ERROR_INVALID:
            reportInvalid();
            break;
        default:
            break;
        }
    }
    bool doEpilog(ref XmlReturn ret)
    {
        dchar test = 0;
        string content;

        while(!empty)
        {
            munchSpace();
            if (empty)
                break;
            if (front != '<')
            {
                throwNotWellFormed("illegal data at end document");
            }

            markupDepth_++;

            popFront();
            if (empty)
                throwNotWellFormed("unmatched markup");
            switch(front)
            {
            case '?': // processing instruction or xmldecl
				markupDepth_--;
				setSingleCharPos(srcIX_-1);
                return doProcessingInstruction(ret); // what else to do with PI'S?
            case '!':
				if (empty)
					ThrowEmpty();
				popFront();
                if (matchInput(COMMENT_d))
                    return doCommentContent(ret);
                goto default;
            default:
                throw getBadCharError(test);
            }
        }
        state_ = PState.P_END;
        return false; // end of document
    }
    final bool refToChar(ref dchar c, ref uint radix)
    {
        dchar test;
        int digits = 0;
        radix = 10;

        if (empty)
            ThrowEmpty();

        test = front;

        if (test == 'x')
        {
            popFront();

            radix = 16;
            if (empty)
                throwNotWellFormed(ParseErrorCode.BAD_ENTITY_REFERENCE);
            test = front;
        }
        int 	n = 0;
        uint	value = 0;

        while(test == '0')
        {
            popFront();
            if (empty)
                throwNotWellFormed(ParseErrorCode.BAD_ENTITY_REFERENCE);
            test = front;
        }
        if (radix == 10)
        {
            while(true)
            {
                if (( test >= '0') && ( test <= '9'))
                {
                    n = (test - '0');
                    value *= 10;
                    value += n;
                    digits++;
                }
                else
                    break; // not part of number

                popFront();
                if (empty)
                    throwNotWellFormed(ParseErrorCode.BAD_ENTITY_REFERENCE);
                if (digits > 10)
                    throwNotWellFormed(ParseErrorCode.BAD_ENTITY_REFERENCE);
                test = front;
            }
        }
        else
        {
            while(true)
            {
                if (( test <= '9') && (test >= '0'))
                    n = (test - '0');
                else if ((test <= 'F') && (test >= 'A'))
                    n = (test - 'A') + 10;
                else if ((test <= 'f') && (test >= 'a'))
                    n = (test - 'a') + 10;
                else
                    break;// not part of number
                digits++;
                value *= 16;
                value += n;

                popFront();
                if (empty)
                    throwNotWellFormed(ParseErrorCode.BAD_ENTITY_REFERENCE);
                if (digits > 8)
                    throwNotWellFormed(ParseErrorCode.BAD_ENTITY_REFERENCE);
                test =  front;
            }
        }
        if (test != ';')
        {
            throwNotWellFormed(ParseErrorCode.BAD_ENTITY_REFERENCE);
        }
        popFront();
        c = value;
        return true;
    }

    dchar expectedCharRef(ref uint radix)
    {
        if (empty)
            ThrowEmpty();
        if (front != '#')
            throw getBadCharError(front);
        popFront();
        dchar result;
        if (!refToChar(result,radix))
        {
            if (empty)
                ThrowEmpty();
            throwNotWellFormed("error in character reference");
        }
        else
        {
            if (
                ((XMLVersion < 1.1) && !isChar10(result))
                ||  ( !isChar11(result) && !isControlCharRef11(result))
            )
            {
                throw getBadCharError(result);
            }
        }
        return result;
    }

	/** got a <! and put it back */
	final bool doBang(ref XmlReturn ret)
	{
		markupDepth_++;
		setSingleCharPos(srcIX_ + 2);
		if (matchInput(CDATA_d))
		{
			squareDepth_ += 2;
			return doCDATAContent(ret);
		}
		else if (matchInput(COMMENT_d))
		{
			return doCommentContent(ret);
		}
		throwNotWellFormed(ParseErrorCode.CDATA_COMMENT);
		assert(0);
	}
    /** Entities may need replacing, prepare to substitute source text */

    final bool doContent(ref XmlReturn ret)
    {
        size_t contentIX = srcIX_;

        content_.length = 0;

        string ename;

        bool  inCharData = false; // indicate that at least one character has been found
        bool  isSubstitute = false; // modified from source.
        intptr_t  replaceIX = 0;  // for goSubstite, last valid srcIX_;

        //dchar  test = 0;
        void goSubstitute()
        {
            if (!isSubstitute)
            {
                isSubstitute = true;
                content_.put(source_[contentIX .. replaceIX]);
            }
        }
        bool returnTextContent(int negadjust)
        {
            // encountered non-content character, return content block
            ret.type = XmlResult.STR_TEXT;
			if (negadjust > 0)
			{
				setSingleCharPos(srcIX_-negadjust);
			}
            if (isSubstitute)
                ret.scratch = content_.idup;
            else
                ret.scratch = source_[contentIX .. srcIX_];
            itemCount++;
            return true;
        }

        while (true)
        {
            if (empty)
            {
                if (totalElementDepth() > 0)
                    throwNotWellFormed(ParseErrorCode.UNEXPECTED_END);
                if (inCharData)
                    return returnTextContent(0);
                else
                    return false;
            }
			if (front == '<')
			{
                markupDepth_++;
                popFront();
                if (empty)
                    ThrowEmpty();

                switch(front)
                {
                case '/':
					markupDepth_--;
					setSingleCharPos(srcIX_-1);
                    if (inCharData)
                    {
                        state_ = PState.P_ENDTAG;
                        return returnTextContent(0);
                    }
                    return doEndTag(ret);
                case '?':
					markupDepth_--;
					setSingleCharPos(srcIX_-1);
                    if (inCharData)
                    {
                        state_ = PState.P_PROC_INST;
                        return returnTextContent(0);
                    }
                    return doProcessingInstruction(ret);
                case '!': // comment or cdata
					markupDepth_--;
					setSingleCharPos(srcIX_-1);
					if (inCharData)
					{
						state_ = PState.P_BANG;
						return returnTextContent(0);
					}
					return doBang(ret);
                default:
                    // no pop front
                    if (isNameStartFn(front) || isNameStartFifthEdition(front))
                    {
						state_ = PState.P_TAG;
						markupDepth_--; // pretend not seen
						setSingleCharPos(srcIX_-1);
                        if (inCharData)
                        {
                            return returnTextContent(0);
                        }
						return doStartTag(ret);
                    }
                    else
                    {
                        /// trick conformance issue
                        estk_.pushMsg(getErrorCodeMsg(ParseErrorCode.TAG_FORMAT),ParseError.fatal);
                        throw getBadCharError(front);
                    }
                } // end switch
			}
            else if (front=='&')
			{  //  reference in content
                replaceIX = srcIX_;
                popFront();
                if (!empty)
                {
                    uint radix;
                    if (front == '#')
                    {
                        goSubstitute();
                        dchar test = expectedCharRef(radix);
                        content_.put(test);
                        inCharData = true;
                        continue;
                    }
                    else if (getXmlName(ename))
                    {
                        if (empty || front != ';')
                            throwNotWellFormed(ParseErrorCode.BAD_ENTITY_REFERENCE);
                        popFront();
                        auto pc = ename in charEntity;
                        if (pc !is null)
                        {
                            goSubstitute();
                            content_.put(*pc);
                            inCharData = true;
                            continue;
                        }

                        if (!decodeEntityReference(ename, false))
                        {
                            goSubstitute();
                            content_.put('&');
                            content_.put(ename);
                            content_.put(';');
                            // TODO: consider returning EntityReference.
                        }
                        continue;
                    }
                }
                throwNotWellFormed("expected entity");
			}
			else 
			{
				if ((front == ']') && (matchInput(CDATA_END1_d)))
                    throwNotWellFormed("illegal CDATA end ]]>");
                if (isSubstitute)
                    content_.put(front);
                popFront();
                inCharData = true;
            } // end switch
        } // WHILE TRUE

        assert(0);
    }
    public void setEntityValue(string entityName, string value)
    {
        if (charEntity.length == 0)
            charEntity = stdCharEntityMap();

        charEntity[entityName] = value;
    }

    // A speedbump
    public string attributeNormalize(string value)
    {
        void noLTChar()
        {
            throwNotWellFormed("< not allowed in attribute value");
        }

        void noSingleAmp()
        {
            throwNotWellFormed("single '&' not allowed");
        }

        version(speedBump)
        {


        //auto pp = contextPopper(this, value);

        intptr_t speedbump = -1;
    PRE_SCAN:
        for(auto ix = 0; ix < value.length; ix++)
        {
            switch(value[ix])
            {
            case '<':
                noLTChar();
                break;
            case '&':
                speedbump = ix;
                break PRE_SCAN;
            default:
                break;
            }
        }
        if (speedbump < 0)
            return value;
        normValue_.length = 0;
        normValue_.put(value[0..speedbump]);
        value = value[speedbump..$];
        }
        else {
            Array!char normValue_;
        }

        pushContext(value,true,null);
        scope(exit)
            popContext();
        bool isSubstitute = false;

        while(!empty)
        {
            if (isSpace(front))
            {
                normValue_.put(' ');
                popFront();
                continue;
            }
            else if (front == '<')
            {
                noLTChar();
            }
            else if (front == '&')
            {
                popFront();
                if (empty)
                    noSingleAmp();

                if (front == '#')
                {
                    uint radix;
                    dchar cref = expectedCharRef(radix);
                    normValue_.put(cref);
                    continue;
                }
                string entityName;
                // getXmlName uses scratch_
                if (!getXmlName(entityName) || !matchInput(';'))
                    noSingleAmp();

                auto pc = entityName in charEntity;
                if (pc is null)
                {
                    if (!decodeEntityReference(entityName, true))
                    {   /// a cop out.
                        normValue_.put('&');
                        normValue_.put(entityName);
                        normValue_.put(';');
                    }
                }
                else
                {
                    normValue_.put(*pc);
                }
            }
            else
            {
                normValue_.put(front);
                popFront();
            }
        }

        return normValue_.idup;
    }
    bool isNmToken(const(char)[] dval)
    {
        if(dval.length == 0)
            return false;
        uintptr_t ix = 0;
        while(ix < dval.length)
        {
            if (!isNameCharFn(decode(dval,ix)))
                return false;
        }
        return true;
    }
    /// return true if entire name is XML name
    bool isXmlName(const(char)[] dval)
    {
        if(dval.length == 0)
            return false;
        uintptr_t ix = 0;
        dchar test = decode(dval, ix);
        if (!(isNameStartFn(test) ||  isNameStartFifthEdition(test)))
            return false;
        while (ix < dval.length)
        {
            test = decode(dval, ix);
            if (! (isNameCharFn(test) ||  isNameCharFifthEdition(test)) )
                return false;
            if (test == ':' && namespaceAware)
                return false;
        }
        return true;
    }

    /// Not implemented. Return current input context as string with replaced character references
    bool expandEntityData(out string result, StringSet stk, out int refType)
    {
        return false;
    }

     /// Not implemented. Return current input context as string with replaced character references
    bool textReplaceCharRef(out string opt)
    {
        return false;
    }

    /// Not implemented. From entity source, and flag internal/external entity , replace all general entities. Mark those encountered in StringSet stk.
    bool textReplaceEntities(bool isInternal, string src, ref string opt, ref StringSet stk)
    {
        return false;
    }
    /// Not implemented.
    bool getSystemPath(string sysid, out string uri)
    {
        return false;
    }


}





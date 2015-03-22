/**

XML parsing according to the standard is expected to do a few ackward things
not easily handled with a simple string slicing approach.
DTDValidate		            dtd_
This includes
Line ending normalisation, where 0xD and other special characters replaced with 0xA.
Source character preprocessing differs slightly between XML 1.0 and 1.1.

Handle the Byte-Order-Mark data in a file, and validate the declared encoding against it.
Handle DTD, defined text entities, replace character and standard entity.
Normalisation and text replacement that might occur in attribute values, and character data.

*/

module xmlp.xmlp.xmlparse;

import alt.zstring,  xmlp.xmlp.charinput, xmlp.xmlp.error, xmlp.xmlp.subparse;
import xmlp.xmlp.feeder, xmlp.xmlp.parseitem, xmlp.xmlp.xmlchar;

import std.conv, std.string,  std.utf, std.variant;
import std.file, std.path;

import xmlp.xmlp.dtdtype, xmlp.xmlp.dtdvalidate, xmlp.xmlp.entitydata;

/// TagStack .  adds tag matching check. Seems to slow performance a tiny bit.
version=TagStack;
/**
Parser, uses mutable character buffers.
*/

/// if custom string allocation
//version=StrAllocation;

version=speedBump; // for attributeNormalize optimization

class XmlParser : ParseSource, IXMLParser
{
package:
    Array!char          tagScratch_;
    Array!char	        attScratch_; // attribute normalisation
    Array!char          entityName_;
    Array!char          content_;
    version(speedBump)
		Array!char          normalizeBuf_;

public:	
    ErrorStack errorStack()
    {
        return estk_;
    }

    private void init2()
    {
        estk_ = new ErrorStack();
        this.exceptionDg = &SourceException;
        this.onEmptyDg = &onInputEmpty;
        isStandalone_ = true;
        charEntity_ = stdCharEntityMap();
        content_.reserve(256);
        scratch_.reserve(64);
        tagScratch_.reserve(64);
        attScratch_.reserve(64);

        version(speedBump)
        normalizeBuf_.reserve(32);

        version (TagStack)
        tagStack_.reserve(16);
    }

    /// construct with text source provider
    this(DataFiller df = null, double xmlver = 1.0)
    {
        super(df, xmlver);
        init2();

    }
    this(string s)
    {
        auto buffer = new SliceFill!char(s);
        this(buffer);
    }

	~this()
	{
		//version(CustomAA)
			//charEntity_.clear();
	}

    /// construct and provide important bits later
    this()
    {
        super();
        init2();
    }

    override void initParse(DataFiller df, double xmlver = 1.0)
    {
        super.initParse(df, xmlver);
        setXMLVersion(xmlver);
        estk_.clear();
        isStandalone_ = true;

    }
    /// differences in XML names for version 1.0, 1.1
    override void setXMLVersion(double val)
    {
        /// check the version is really known

        if ((val != 1.0) && (val != 1.1))
        {
            uint major = cast(uint) val;
            if (major != 1 || maxEdition < 5)
                doParseError(text("XML version not supported ",val));
        }


        if (master_ !is null)
        {
            double masterVersion = master_.xmlVersion();

            if (val > masterVersion )
            {
                string msg = format("External entity xml version is %3.1f, document is %3.1f", val, masterVersion);

                doNotWellFormed(msg);
            }
        }
        docVersion_ = val;
        if (val >= 1.1)
        {
            isNameStartFn_ = &isNameStartChar11;
            isNameCharFn_ = &isNameChar11;
        }
        else
        {
            isNameStartFn_ = &isNameStartChar10;
            isNameCharFn_ = &isNameChar10;
        }
    }
public:
    /// interface requirements
    EntityData entityContext()
    {
        return entity_;
    }
    void entityContext(EntityData val)
    {
        entity_ = val;
    }
    ErrorStack getErrorStack()
    {
        return estk_;
    }
    bool isStandalone() const
    {
        return isStandalone_;
    }
    bool validate() const
    {
        return validate_;
    }
    void validate(bool val)
    {
        validate_ = val;
    }
    bool namespaces() const
    {
        return namespaceAware_;
    }
    void namespaces(bool doNamespaces)
    {
        namespaceAware_ = doNamespaces;
    }

    IDValidate idSet()
    {
        return idValidate_;
    }

    void createIdSet()
    {
        idValidate_ = new IDValidate();
    }
    void pushContext(string data, bool inScope, EntityData edata)
    {
        doPushContext(data,inScope,edata);
    }
    void popContext()
    {
        doPopContext();
    }
    string attributeNormalize(string src)
    {
        return doAttributeNormalize(src);
    }
    bool textReplaceCharRef(out string opt)
    {
        return doReplaceCharRef(opt);
    }
    bool inGeneralEntity() const
    {
        return isInGeneralEntity();
    }
    bool inParamEntity() const
    {
        return isInParamEntity();
    }
    bool inDTD()
    {
        return inDTD_;
    }
    string getEntityName()
    {
        return entityName();
    }
    bool isNmToken(const(char)[] dval)
    {
        return isNmTokenImpl(dval);
    }
    /// return true if entire name is XML name
    bool isXmlName(const(char)[] dval)
    {
        return isXmlNameImpl(dval);
    }
    void systemPaths(string[] paths)
    {
        systemPaths_ = paths;
    }
    string[] systemPaths()
    {
        return systemPaths_;
    }
    bool getSystemPath(string sysid, out string uri)
    {
        return getSystemPathImpl(sysid,uri);
    }
    public void setEntityValue(string entityName, string value)
    {
        charEntity_[entityName] = value;
    }

    void throwErrorCode(ParseErrorCode code)
    {
        doParseError(code);
    }

    void throwNotWellFormed(string msg)
    {
        doParseError(msg,ParseError.fatal);
    }
    void throwUnknownEntity(string ename)
    {
        doUnknownEntity(ename);
    }
    public override void setReportInvalidDg(ReportInvalidDg dg)
    {
        reportInvalid_ = dg;
    }
    public override ReportInvalidDg getReportInvalidDg()
    {
        return reportInvalid_;
    }
    void setPrepareThrowDg(PrepareThrowDg dg)
    {
        prepareExDg = dg;
    }
    PrepareThrowDg getPrepareThrowDg()
    {
        return prepareExDg;
    }
	// Set the parser to return with immediate detection of start tag end.
	// Used in network streams.
	// May prevent automatic detection of TAG_EMPTY.

	void fragmentReturn(bool value)
	{
		isFragment = value;
		if (isFragment)
			this.onEmptyDg = &fragmentEndNotify;
		else
			this.onEmptyDg = &onInputEmpty;
	}
    void setParameter(string name, Variant n)
    {
		switch(name)
		{
		case xmlAttributeNormalize:
			normalizeAttributes = n.get!bool;
			break;

		case "fragment":
			fragmentReturn(n.get!bool);
			break;

		case xmlNamespaces:
			namespaceAware_ = n.get!bool;
			break;
		case xmlCharFilter:
			if (n.get!bool == false)
            {
                filterAlwaysOff();
            }
			break;
		case "edition":
			{
				maxEdition = n.get!uint;
			}
			break;
		default:
			break;
		}
    }
    double xmlVersion()
    {
        return XMLVersion;
    }
    void initParse()
    {
        pumpStart();
    }
    bool parse(ref XmlReturn ret)
    {
		if (pendingPop)
		{	// Jabber adaptation
			pendingPop = false;
			popFront();
		}		

        switch(state_)
        {
        case PState.P_DATA:
            return doContent(ret);

        case PState.P_TAG:
            return doStartTag(ret);
			
        case PState.P_ENDTAG:
            return doEndTag(ret);

        case PState.P_CDATA:
            return doCDATAContent(ret);

        case PState.P_COMMENT:
            return doCommentContent(ret);

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
    void getLocation(ref SourceRef sref)
    {
        sref.charsOffset = cast(int) srcRef_;
        sref.lineNumber = lineNumber_;
        sref.colNumber = lineChar_;
    }
    bool expandEntityData(out string result, StringSet stk, out int refType)
    {
        return doExpandEntityData(result,stk,refType);
    }

protected:
    enum
    {
        SRC_BUF_SIZE = 64
    }


    string[]			    systemPaths_;
    IXMLParser				master_; // called from another instance

    CharTestFn			    isNameStartFn_;
    CharTestFn			    isNameCharFn_;


    ProcessingInstructionDg		onProcessingInstruction_;  // callback
    ReportInvalidDg	            reportInvalid_;

    uint			maxEdition = 5;
    ErrorStack		estk_;
    bool			validate_;
    bool			isStandalone_;
    bool			isEntity;
    bool            inDTD_;

    // has declared in XML declaration.
    bool    hasDeclaration;
    bool    hasStandalone;
    bool    hasEncoding;
    bool    hasXmlVersion;
	// Jabber adaptation, delay final popFront, no empty tag check for document element
	// 
	bool	isFragment; 
	bool	pendingPop;
	bool	normalizeAttributes; // set on if not doing customized handling

	/// more carefully check
	void fragmentEndNotify()
	{
		if (contextStack_.length > 0)
		{
			onInputEmpty(); // call the other onEmpty delegate
		}
		else
			state_ = PState.P_END;
	}
	
    StdEntityMap                charEntity_;

    version (StrAllocation) ImmuteAlloc!(char)	strAlloc_;

    Array!char	scratch_; // stay around buffer for non re-entrent functions
    //string[string]		tagNameMap;

    // markup depth required for XML declaration.
    int			markupDepth_;
    int			itemCount;
    bool		namespaceAware_;
    int			elementDepth_;
    int			squareDepth_;
    int			parenDepth_;
    bool		scopePop_;

    Array!SavedContext	contextStack_;

    int					stackElementDepth_;
    DTDValidate			dtd_;			// entity definitions
    IDValidate			idValidate_;

    version(TagStack)
    {
        Array!string      tagStack_; // check and resuse tag strings
        string            lastCloseTag_;         // for starting tag thats the same as previous start tag
    }

    final void onInputEmpty()
    {
        // if we are scoped then want none of this
        if (scopePop_) // either this or put the NotifyEmpty delegate in the saved context
            return;

        checkBalanced();
        auto slen = contextStack_.length;
        if (slen > 0)
        {
            slen--;
            if (isInParamEntity)
            {
                auto p = contextStack_.last();
                p.squareDepth += this.squareDepth_;
                p.markupDepth += this.markupDepth_;
                p.elementDepth += this.elementDepth_;
                p.parenDepth += this.parenDepth_;
                stackElementDepth_ += this.elementDepth_;
            }

            if (!scopePop_)
            {
                doPopContext();
            }
        }
    }

    /// give exceptions a chance to be examined, add context to error message.
    string getErrorMessage(string exmsg)
    {

        if (entity_ !is null)
        {
            estk_.pushMsg(text("Error in entity context: ", entity_.name_));
            if (entity_.src_.systemId_ !is null)
                estk_.pushMsg(text("System id: ",entity_.src_.systemId_));
        }

        string msg2 = estk_.toString();
        estk_.clear();

        auto slen = contextStack_.length;
        foreach(ix, ref ctx ; contextStack_.toArray)
        {
            estk_.pushMsg(getErrorContext());
            estk_.pushMsg(text("Context_:",ix+1));
        }
        estk_.pushMsg(msg2);
        estk_.pushMsg(getErrorContext());
        estk_.pushMsg(exmsg);
        if (entity_ !is null)
        {
            estk_.pushMsg(text("Entity name ", entity_.name_));
        }
        string result = estk_.toString();
        estk_.clear();
        return result;
    }

    string balanceMismatchMsg()
    {
        scratch_.length = 0;
        if (squareDepth_ != 0)
            scratch_.put(" mismatch of [ ]");
        if (markupDepth_ != 0)
            scratch_.put(" mismatch of < > ");
        if (elementDepth_ != 0)
            scratch_.put(" mismatch of element depth");
        if (parenDepth_ != 0)
            scratch_.put(" mismatch of ( )");

        return scratch_.idup;
    }

    final void checkBalanced()
    {
        if ((squareDepth_ != 0) || (markupDepth_ != 0) || (elementDepth_ != 0) || (parenDepth_ != 0))
        {
            if (!isInParamEntity || (markupDepth_ > 0) )
            {
                // do not understand the difference between xmltest\invalid--005 and not-wf-not-sa-009
                doNotWellFormed(text("Imbalance on end context: ", balanceMismatchMsg()));
            }
            else
            {
                if (elementDepth_ != 0)
                {
                    doNotWellFormed("unbalanced element in entity content");
                }
                else if ((squareDepth_==0) && (parenDepth_ != 0))
                {
                    if (validate_)
                        estk_.pushMsg("parenthesis mismatch across content source",ParseError.invalid);
                }
                else if (validate_)
                    estk_.pushMsg(text("Bad content nesting in entity ",balanceMismatchMsg()),ParseError.invalid);
            }
        }
    }

    /// call back for Processing Instructions
    void setProcessingInstructionDg(ProcessingInstructionDg dg)
    {
        onProcessingInstruction_ = dg;
    }

    //@property ErrorStack errorStack() { return estk_; }

    /// important , should be property.


    /*
    protected void copyAttributes(ref XmlReturn r)
    {
    	auto attCount = attNames_.length;
    	if (attCount > 0)
    	{
    		this.names_.length = attCount;
    		this.values_.length = attCount;

    		r.names = attNames_.idup(this.names_.toArray, strAlloc_);
    		r.values = attValues_.idup(this.values_.toArray, strAlloc_);
    	}
    	else {
    		r.names = null;
    		r.values = null;
    	}
    }
    */
    /** Save context for parsing parmeter and parsed entities */
    protected struct SavedContext
    {
        dchar				front_;
        bool				empty_;
        double				docVersion;
        dchar				lastChar;
        size_t				nextpos;
        size_t				lineNumber;
        size_t				lineChar;
        dchar[]				buffer;
        Array!dchar	        stack;

        DataFiller			dataFiller;

        CharFilter			doFilter;
        bool				isEndOfLine;
        ulong				srcRef;
        int					markupDepth;
        int					elementDepth;
        int					squareDepth;
        int					parenDepth;
        EntityData			entity;
        bool				scopePop;
    }

    void restoreContext(ref SavedContext ctx)
    {
        with(ctx)
        {
            front = front_;
            empty = empty_;
            docVersion = docVersion_;

            lastChar_ = lastChar;
            nextpos_ = nextpos;
            lineNumber_ = lineNumber;
            lineChar_ = lineChar;
            buffer_ = buffer;
            stack_ = stack;
            dataFiller_ = dataFiller;
            doFilter_ = doFilter;
            isEndOfLine_ = isEndOfLine;
            srcRef_ = srcRef;
            markupDepth_ = markupDepth;
            elementDepth_ = elementDepth;
            squareDepth_ = squareDepth;
            parenDepth_ = parenDepth;
            entity_ = entity;
            scopePop_ = scopePop;
        }
    }

    void doPopContext()
    {
        auto slen = contextStack_.length;
        if (slen > 0)
        {
            slen--;
            restoreContext(*contextStack_.last);
            contextStack_.length = slen;
            if (slen > 0)
                stackElementDepth_ -= elementDepth_;
            else
                stackElementDepth_ = 0;
        }
    }

    void doPushContext(string s, bool scoped, EntityData ed)
    {
        SavedContext ctx;

        saveContext(ctx);

        auto slen = contextStack_.length;

        if (slen == 0)
            stackElementDepth_ = elementDepth_;
        else
            stackElementDepth_ += elementDepth_;
        contextStack_ ~= ctx;
        initContext(s, scoped, ed);
        pumpStart();
    }

    void initContext(const(char)[] s, bool scoped, EntityData ed = null)
    {
        front = 0;
        empty = true;
        lastChar_ = 0;

        nextpos_ = 0;
        lineNumber_ = 0;
        lineChar_ = 0;
        buffer_ = null;
        stack_.length = 0;
        dataFiller_ = new SliceFill!char(s);
        isEndOfLine_ = false;
        srcRef_ = 0;
        markupDepth_ = 0;
        elementDepth_ = 0;
        squareDepth_ = 0;
        parenDepth_ = 0;
        entity_ = ed;
        scopePop_ = scoped;
        if (scoped || ed !is null)
            filterAlwaysOff();
    }
    void saveContext(ref SavedContext ctx)
    {
        with(ctx)
        {
            front_ = front;
            empty_ = empty;
            docVersion = docVersion_;

            lastChar = lastChar_;
            nextpos = nextpos_;
            lineNumber = lineNumber_;
            lineChar = lineChar_;
            buffer = buffer_;
            stack = stack_;
            dataFiller = dataFiller_;
            doFilter = doFilter_;

            isEndOfLine = isEndOfLine_;
            srcRef = srcRef_;
            markupDepth = markupDepth_;
            elementDepth = elementDepth_;
            squareDepth = squareDepth_;
            parenDepth = parenDepth_;
            entity = entity_;
            scopePop = scopePop_;
        }
    }
public:

    void setSystemPaths(string[] paths)
    {
        systemPaths_ = paths;
    }

    void SourceException(Exception x)
    {
        ParseError pe = cast(ParseError) x;
        if ( pe is null)
        {
            string msg = x.toString();
            throw prepareThrow(new ParseError(msg));
        }
        else
        {
            throw prepareThrow(pe);
        }
    }
    void reportInvalid()
    {
        auto estk = errorStack();
        if (estk.errorStatus() > 0)
        {
            if (reportInvalid_ !is null)
            {
                string msg = estk.toString();
                reportInvalid_(msg);
            }
            estk.clear();
        }
    }

    public void throwParseError(string s)
    {
        throw prepareThrow(new ParseError(s, ParseError.error));
    }

    /// give exceptions a chance to be examined
    public ParseError prepareThrow(ParseError x)
    {
        /*
        if (master)
        	return master.prepareThrow(x);
        else
        	return x;
        */
        if (prepareExDg)
            return prepareExDg(x);
        else
            return x;
    }

    void doPrematureEnd()
    {
        Exception ex = prepareThrow(new ParseError("Unexpected end document"));
        if (ex !is null)
            throw ex;
    }
    void doNotWellFormed(ParseErrorCode code)
    {
        Exception ex = prepareThrow(new ParseError(code, ParseError.fatal));
        if (ex !is null)
            throw ex;
    }
    void doNotWellFormed(string msg)
    {
        doParseError(msg, ParseError.fatal);
    }
    void doParseError(string msg, int level = ParseError.error)
    {
        Exception ex = prepareThrow(new ParseError(msg, level));
        if (ex !is null)
            throw ex;
    }

    void doParseError(ParseErrorCode code)
    {
        Exception ex = prepareThrow(new ParseError(code, ParseError.fatal));
        if (ex !is null)
            throw ex;
    }
    void ThrowBadCharacter(dchar c, uint severity = ParseError.fatal)
    {
        throw prepareThrow(new ParseError(badCharMsg(c),severity));
    }

    void ThrowEmpty()
    {
        doErrorCode(ParseErrorCode.UNEXPECTED_END);
    }

    void doErrorCode(ParseErrorCode code)
    {
        Exception ex = prepareThrow(new ParseError(code,ParseError.fatal));
        if (ex !is null)
            throw ex;
    }

    Exception getBadCharError(dchar c, uint severity = ParseError.fatal)
    {
        return prepareThrow(new ParseError(badCharMsg(c),severity));
    }


    /// for validation conformance test.
    /// Report that XML version 1.0 has characters which are not name start for
    /// Parsers configured earlier than fifth edition.

    bool isNameStartFifthEdition(dchar test)
    {
        if (docVersion_ == 1.0 && maxEdition >= 5)
        {
            if (!isNameStartChar11(test))
                return false;

            if (validate_)
            {
                errorStack().pushMsg("Name start character only specified by XML 1.0 fifth edition",ParseError.invalid);
                reportInvalid();
            }
            return true;
        }
        return false;
    }
    bool isNameCharFifthEdition(dchar test)
    {
        if (docVersion_ == 1.0 && maxEdition >= 5)
        {
            if (!isNameChar11(test))
                return false;

            if (validate_)
            {
                errorStack().pushMsg("Name character only specified by XML 1.0 fifth edition",ParseError.invalid);
                reportInvalid();
            }
            return true;
        }
        return false;
    }

    /** Very testy function.  Attributes are not acted on until the whole declaration is parsed!

    	*/
    bool doXmlDeclaration(ref XmlReturn ret)
    {
        double xml_value = 1.0;
        string atname;
        string atvalue;

        //state_ = XML_DECLARATION;
        int spaceCt =  munchSpace();
        size_t atcount = 0;
        isStandalone_ = false; // if has an xml declaration, assume false as default

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
            if (!getXmlName(scratch_))
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
                    doNotWellFormed("expected ?>");
                    break;
                case '\'':
                case '\"':
                    doNotWellFormed("expected attribute name");
                    break;
                case 0x85:
                case 0x2028:
                    if (xml_value == 1.1)
                        doParseError(format("%x illegal in declaration", badChar));
                    goto default;
                default:
                    doNotWellFormed(badCharMsg( badChar));
                }
            }
			version(StrAllocation)
				atname =  strAlloc_.alloc(scratch_.toArray);
			else
				atname = scratch_.idup;

             if  (!spaceCt)
                doNotWellFormed("missing spaces");

            if (!getAttributeValue(scratch_) || scratch_.length==0)
                doNotWellFormed("declaration value expected");

            version(StrAllocation)
				atvalue = strAlloc_.alloc(scratch_.toArray);
			else
				atvalue = scratch_.idup;
   
			
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
                dataFiller_.setBufferSize(1);
                break;
            case "standalone":
                if (isEntity)
                    doNotWellFormed("standalone illegal in external entity");
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
                doNotWellFormed(text("unknown declaration attribute ", atname));
                break;
            }
            spaceCt = munchSpace();
        }
        if (hasXmlVersion)
            setXMLVersion(xml_value);

        markupDepth_--;
        if (isEntity && !hasEncoding)
            doNotWellFormed("Optional entity text declaration must have encoding=");
        checkErrorStatus();
        ret.type = XmlResult.XML_DEC;
        ret.scratch = null;

		if (hasEncoding)
			setXmlEncoding(ret.attr["encoding"]);
		if (hasStandalone)
			setXmlStandalone(ret.attr["standalone"]);

        dataFiller_.setBufferSize(SRC_BUF_SIZE); // seems to make little difference in overall times
        itemCount++;
        return true;
    }


    /** parse  = S* "value"  */

    final bool getAttributeValue(ref Array!char app)
    {
        munchSpace();
        dchar test;
        if (empty || (front != '='))
            doErrorCode(ParseErrorCode.EXPECTED_ATTRIBUTE);
        popFront();
        munchSpace();
        if (!unquoteValue(app))
            doErrorCode(ParseErrorCode.EXPECTED_ATTRIBUTE);
        return true;
    }

    /** unpack quoted character string */

    final bool unquoteValue(ref Array!char app)
    {
        dchar enquote = (empty ? 0x00 : front);
        if ((enquote != '\'') && (enquote != '\"'))
        {
            doErrorCode(ParseErrorCode.MISSING_QUOTE);
            return false;
        }
        popFront();
        frontFilterOn();
        app.length = 0;
        while(!empty)
        {
            if (front == enquote)
            {
                popFront();
                return true;
            }
            else
            {
                app.put(front);
                popFront();
            }
        }
        doErrorCode(ParseErrorCode.MISSING_QUOTE);
        return false;
    }
    ///  True if next input has <?
    final bool isPIStart()
    {
        if (!empty && (front == '<'))
        {
            markupDepth_++;
            frontFilterOff();
            popFront();
            if (!empty && (front == '?'))
            {
                popFront();
                return true;
            }
            markupDepth_--;
            pushFront('<');
        }
        return false;
    }
    /// check and convert the version string value, has to be number with decimal point
    double doXmlVersion(const(char)[] xmlversion)
    {
        scratch_.length = 0;
        auto sf = new SliceFill!(char)(xmlversion);
        auto ps = new ParseSource(sf);
        ps.pumpStart();
        NumberClass nc = parseNumber(ps, scratch_);

        //auto vstr = scratch_.toArray;
        if (nc != NumberClass.NUM_REAL)
            doNotWellFormed(text("expect 1.0/1.1",xmlversion));
        if (scratch_.length < xmlversion.length)
            doNotWellFormed("additional text in xml version");
        return  to!double(scratch_.toArray);
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
            doNotWellFormed(text("Bad encoding name: ", encoding));
        }
        // prepare to fail low level
        try
        {
            dataFiller_.setEncoding(encoding);
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
        dataFiller_.setBufferSize(SRC_BUF_SIZE);
    }
    void setXmlStandalone(const(char)[] standalone)
    {
        if (standalone == "yes")
            isStandalone_ = true;
        else if (standalone == "no")
            isStandalone_ = false;
        else
            doNotWellFormed(text("Bad standalone value: ",standalone));
    }

    protected void checkErrorStatus()
    {
        switch(estk_.errorStatus)
        {
        case XML_ERROR_FATAL:
            doNotWellFormed("fatal errors");
            break;
        case XML_ERROR_ERROR:
            doParseError("errors");
            break;
        case XML_ERROR_INVALID:
            reportInvalid();
            break;
        default:
            break;
        }
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
                doParseError(ParseErrorCode.BAD_ENTITY_REFERENCE);
            test = front;
        }
        int 	n = 0;
        uint	value = 0;

        while(test == '0')
        {
            popFront();
            if (empty)
                doParseError(ParseErrorCode.BAD_ENTITY_REFERENCE);
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
                    doParseError(ParseErrorCode.BAD_ENTITY_REFERENCE);
                if (digits > 10)
                    doParseError(ParseErrorCode.BAD_ENTITY_REFERENCE);
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
                    doParseError(ParseErrorCode.BAD_ENTITY_REFERENCE);
                if (digits > 8)
                    doParseError(ParseErrorCode.BAD_ENTITY_REFERENCE);
                test =  front;
            }
        }
        if (test != ';')
        {
            doParseError(ParseErrorCode.BAD_ENTITY_REFERENCE);
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
            doNotWellFormed("error in character reference");
        }
        else
        {
            if (
                ((docVersion_ < 1.1) && !isChar10(result))
                ||  ( !isChar11(result) && !isControlCharRef11(result))
            )
            {
                throw getBadCharError(result);
            }
        }
        return result;
    }
    bool isNmTokenImpl(const(char)[] dval)
    {
        if(dval.length == 0)
            return false;
        uintptr_t ix = 0;
        while(ix < dval.length)
        {
            if (!isNameCharFn_(decode(dval,ix)))
                return false;
        }
        return true;
    }
    /// return true if entire name is XML name
    bool isXmlNameImpl(const(char)[] dval)
    {
        if(dval.length == 0)
            return false;
        uintptr_t ix = 0;
        dchar test = decode(dval, ix);
        if (!isNameStartFn_(test) ||  isNameStartFifthEdition(test))
            return false;
        while (ix < dval.length)
        {
            test = decode(dval, ix);
            if (!isNameCharFn_(test) ||  isNameCharFifthEdition(test))
                return false;
            if (test == ':' && namespaceAware_)
                return false;
        }
        return true;
    }
    protected final void expectEntityName(ref Array!char ename)
    {
        if (!getXmlName(ename))
            doErrorCode(ParseErrorCode.BAD_ENTITY_REFERENCE);
        if (empty || front != ';')
            doErrorCode(ParseErrorCode.BAD_ENTITY_REFERENCE);
        popFront(); // pop ;
    }
    protected bool getXmlName(ref Array!char sbuf)
    {
        if (empty)
            return false;
        if ( !( isNameStartFn_(front) || isNameStartFifthEdition(front)) )
            return false;
        frontFilterOff();
        sbuf.length = 0;
        sbuf.put(front);
        popFront();
        while (!empty)
        {
            if (isNameCharFn_(front) || isNameCharFifthEdition(front))
            {
                sbuf.put(front);
                popFront();
            }
            else
                break;
        }
        frontFilterOn();
        return true;
    }
    /// Read from current input context, replacing character references
    protected bool doReplaceCharRef(out string opt)
    {
        uint radix;
        dchar rchar = 0;

        Array!char app;

        while (!empty)
        {
            if (lineChar_ >= 0x3FFA)
            {
                radix = 20;
            }
            if (front == '&')
            {
                //startStackID_ = stackID_;
                popFront();
                if (empty)
                    doPrematureEnd();
                if (front == '#')
                {
                    popFront();
                    refToChar(rchar, radix);
                    app.put(rchar);
                }
                else
                {
                    // process the entity name
                    app.put('&');
                    expectEntityName(entityName_);
                    app.put(entityName_.toArray);
                    app.put(';');
                }
            }
            else
            {
                app.put(front);
                popFront();

            }
        }
        opt = app.unique;
        return (opt.length > 0);
    }
    void handleProcessInstruction(ref XmlReturn iret)
    {
		if (onProcessingInstruction_ !is null)
		{
			auto rec = iret.attr.atIndex(0);
			onProcessingInstruction_(rec.id, rec.value);
		}
    }
    /// got a '[', check the rest
    protected final bool isCDataEnd()
    {
        if (empty || front != ']')
            return false;
        squareDepth_--;
        popFront();
        if (empty || front != ']')
        {
            pushFront(']');
            squareDepth_++;
            return false;
        }
        squareDepth_--;
        popFront();
        if (empty || front != '>')
        {
            pushFront("]]"); // ? allow ]] in CDATA?
            squareDepth_ += 2;
            return false;
        }
        markupDepth_--;
        popFront();
        return true;
    }
    protected final bool matchMarkupBegin(dstring match)
    {
        // whacko, must count each < and [
        size_t lastmatch = 0;
        int addMarkup = markupDepth_;
        int addSquare = squareDepth_;
        //int squareOn = 0;
        dchar	test;

        auto dlen = match.length;

        for(size_t i = 0; i < dlen; i++)
        {
            if (!empty && front==match[i])
            {
                switch(front)
                {
                case '<':
                    addMarkup++;
                    break;
                case '[':
                    addSquare++;
                    break;
                default:
                    break;
                }
                lastmatch++;
                popFront();
            }
            else
            {
                break;
            }
        }
        if (lastmatch == 0)
        {
            return false;
        }
        else if (lastmatch == dlen)
        {
            markupDepth_ = addMarkup;
            squareDepth_ = addSquare;
            return true;
        }
        else
        {
            pushFront( match[0 .. lastmatch] );
            return false;
        }
    }
    protected bool doProcessingInstruction(ref XmlReturn ret, uint spaceCt = 0)
    {
        if (!getXmlName(scratch_))
            doNotWellFormed("Bad processing instruction name");

		version(StrAllocation)
			string xpiName = strAlloc_.alloc(scratch_.toArray);
		else
			string xpiName = scratch_.idup;

		ret.attr.clear();

        if (namespaceAware_ && (indexOf(xpiName,':') >= 0))
            doNotWellFormed(text(": in process instruction name ",xpiName," for namespace aware parse"));

        if (xpiName == "xml")
        {
            if (inDTD_)
                doNotWellFormed("Xml declaration may not be in DTD");
            if (state_ != PState.P_PROLOG || (spaceCt > 0) || (itemCount > 0))
                doNotWellFormed("xml declaration should be first");
            if (!hasDeclaration)
            {
                hasDeclaration = true;
                try
                {
                    return doXmlDeclaration(ret);
                }
                catch (ParseError ex)
                {
                    throw prepareThrow(ex);
                }
            }
            else
                doNotWellFormed("Duplicate xml declaration");
        }
        if ((state_ != PState.P_PROLOG)&&(state_ != PState.P_EPILOG))
            state_ = PState.P_DATA;

        auto lcase = xpiName.toLower();

        if (lcase == "xml")
        {
            doNotWellFormed(text(xpiName," is invalid name"));
        }
		getPIData(scratch_);


        
 		
		version(StrAllocation)
			auto piValue = strAlloc_.alloc(scratch_.toArray);
		else
			auto piValue = scratch_.idup;

		ret.type = XmlResult.STR_PI;

		ret.attr.put(AttributeMap.BlockRec(xpiName,piValue));
		ret.scratch = xpiName;

        itemCount++;
        return true;
    }
    /// Get the data part of a ProcessingInstruction
    /// Check for space between target and content, if there is any content
    protected final void getPIData(ref Array!char app)
    {
        dchar  test  = 0;

        app.length = 0;

        bool	hasContent = false;
        bool	hasSpace = false;

        frontFilterOn();
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
                    if (!hasSpace)
                        doNotWellFormed("space required after target name");
                    app.put(test);
                }
            }
            else
                app.put(test);
        }
    }
    /// return path existing file referenced by the SYSTEM id
    protected bool getSystemPathImpl(string sysid, out string uri)
    {
        uri = sysid;
        bool isAbsolutePath = (std.path.isAbsolute(uri) ? true : false);
        bool found = exists(uri);
        if (!found)
        {
            foreach(s ; systemPaths_)
            {
                string syspath = std.path.buildPath(s, uri);
                found = exists(syspath);
                if (found)
                {
                    isAbsolutePath = (std.path.isAbsolute(syspath) ? true : false);
                    uri = syspath;
                }
            }
        }
        return (found && isFile(uri));
    }
    protected final bool getXmlNmToken(ref Array!char cbuf)
    {
        if (empty)
            return false;
        if ( !(isNameCharFn_(front) || isNameCharFifthEdition(front)) )
            return false;
        cbuf.length = 0;
        cbuf.put(front);

        frontFilterOff();
        popFront();
        while (!empty)
        {
            if (isNameCharFn_(front) || isNameCharFifthEdition(front))
            {
                cbuf.put(front);
                popFront();
            }
            else
            {
                return true;
            }
        }
        if (empty)
            ThrowEmpty();
        return false;
    }
    bool doDocType(ref XmlReturn ret)
    {
        // do limited internal ENTITY, NOTATION?
        doNotWellFormed("DOCTYPE not supported");
        return false;
    }


    final void parseComment(ref Array!char app)
    {
        dchar  test  = 0;
        app.length = 0;
        frontFilterOn();
        while(!empty)
        {
            if (front=='-')
            {
                popFront();
                if (isCommentEnd())
                {
                    return;
                }
                app.put('-');
                continue;
            }
            app.put(front);
            popFront();
        }
        doNotWellFormed("Unterminated comment");
    }

    void doUnexpectedEnd()
    {
        throw  prepareThrow(new ParseError("Unexpected end"));
    }
    bool doCommentContent(ref XmlReturn ret)
    {
        if ((state_ != PState.P_PROLOG) && (state_ != PState.P_EPILOG))
            state_ = PState.P_DATA;

        parseComment(scratch_);
        ret.type = XmlResult.STR_COMMENT;
		version(StrAllocation)
			ret.scratch = strAlloc_.alloc(scratch_.toArray);
		else
			ret.scratch = scratch_.toArray.idup;
        itemCount++;
        return true;
    }

    bool doProlog(ref XmlReturn item)
    {
        dchar testchar;
        string  content;
        int spaceCt;

        item.type = XmlResult.RET_NULL;
        if (itemCount==0)
            pumpStart();

        while(!empty)
        {
            spaceCt = munchSpace();

            if (empty)
                break;

            if (front == '<')
            {
                markupDepth_++;
                frontFilterOff();

                popFront();
                switch(front)
                {
                case '?':
                    popFront();
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
                    doNotWellFormed("Illegal in prolog");
                    goto default;
                default:
                    if (isNameStartFn_(front) || isNameStartFifthEdition(front))
                    {
                        if (!hasDeclaration)
                        {
                            dataFiller_.setBufferSize(SRC_BUF_SIZE);
                            if (validate_ && !inDTD_)
                            {
                                estk_.pushMsg("No xml declaration",ParseError.invalid);
                            }
                        }
                        state_ = PState.P_TAG;
                        return true;
                    }
                    else
                        throw getBadCharError(testchar);
                } // end switch
            } // end peek
            else
            {
                doNotWellFormed("expect xml markup");
            }
            // else?
        } // end while
        doNotWellFormed("bad xml");
        assert(0);
    }

    protected final bool doStartTag(ref XmlReturn r)
    {
        string attName;
        string attValue;

        size_t attCount = 0;
        state_ = PState.P_DATA;

        //markupDepth_++;
        if (!getXmlName(tagScratch_))
            throwParseError("Expected tag name");

        elementDepth_++;
		r.attr.clear();

        int attSpaceCt = 0;
        bool isClosed = false;

        void allocTag()
        {
            version(TagStack)
            {
                auto temp = tagScratch_.toArray;
                if (lastCloseTag_ == temp)
                {
                    r.scratch = lastCloseTag_;
                }
                else
                {
					version(StrAllocation)
						r.scratch = strAlloc_.alloc(temp);
					else
						r.scratch = temp.idup;
                    //lastCloseTag_ = r.scratch;
                }
            }
            else
            {
				version(StrAllocation)
					r.scratch = strAlloc_.alloc( tagScratch_.toArray);
				else
					r.scratch = tagScratch_.idup;
            }
        }

		void checkAttributes()
		{
			if (r.attr.length > 1)
			{
				r.attr.sort;
				auto ix = r.attr.getDuplicateIndex();
				if (ix >= 0)
					doNotWellFormed(ParseErrorCode.DUPLICATE_ATTRIBUTE);
			}
		}

        while (true)
        {
            attSpaceCt = munchSpace();

            if (empty)
                doErrorCode(ParseErrorCode.UNEXPECTED_END);
            frontFilterOff();
            switch(front)
            {
            case '>': // no attributes, but possible inner content
                markupDepth_--;
                
                r.type = XmlResult.TAG_START;
                allocTag();
				checkAttributes();

                //copyAttributes(r); // convert to string(s)
                itemCount++;
				if (isFragment && elementDepth_==1)
				{
					// cannot check for TAG_EMPTY following, ensure TagStack_
					//TAG_START
					version(TagStack)
						tagStack_.put(r.scratch);

					pendingPop = true;
					return true; 
				}
				// if isFragment, needed to delay this, as may cause a blocking input request prior to return
				popFront(); 
				if (empty)
				{
					if (state_ != PState.P_END)
						ThrowEmpty();
					if (isFragment)
						state_ = PState.P_DATA;
					
					return true;
				}
                /* Check for immediate following end tag, which means TAG_EMPTY */
                if (front == '<')
                {
                    markupDepth_++;
                    popFront();
                    if (empty)
                        ThrowEmpty();
                    if (front == '/')
                    {
                        // by strict rules of XML, must be the end tag of preceding start tag.
                        popFront();
                        if (empty)
                            ThrowEmpty();

                        if (!getXmlName(tagScratch_))
                        {
                            doNotWellFormed(ParseErrorCode.ELEMENT_NESTING);
                        }

                        if (tagScratch_.toArray != r.scratch)
                        {
                            doNotWellFormed(ParseErrorCode.ELEMENT_NESTING);
                        }
                        munchSpace();
                        if (empty || (front != '>'))
                        {
                            doNotWellFormed(ParseErrorCode.MISSING_END_BRACKET);
                        }
                        markupDepth_--;
                        elementDepth_--;
                        popFront();
                        r.type = XmlResult.TAG_SINGLE; // signal no content
						checkEndElement(); // important if empty root element
						return true;
                    }
                    else
                    {
                        // recapture later
                        markupDepth_--;
                        pushFront('<');
                    }
                }
				//TAG_START
                version(TagStack)
					tagStack_.put(r.scratch);
                return true;

            case '/':
                popFront();
                if (empty)
                    ThrowEmpty();
                if (front != '>')
                    doErrorCode(ParseErrorCode.TAG_FORMAT);
                markupDepth_--;
                elementDepth_--;
                popFront();
                checkEndElement();
                r.type = XmlResult.TAG_SINGLE;

                allocTag();
				checkAttributes();

                itemCount++;
                return true;

            default:
                if (attSpaceCt == 0)
                {

                    if (attCount == 0)// a non-space character, not a > or a / after xmlname characters
                        doNotWellFormed(format("Bad Xml name character 0x%x", front));
                    else
                        doErrorCode(ParseErrorCode.MISSING_SPACE);
                }
                if (!getXmlName(scratch_))
                {
                    estk_.pushMsg(getErrorCodeMsg(ParseErrorCode.EXPECTED_ATTRIBUTE),ParseError.invalid);
                    throw getBadCharError(front);
                }

                // attributes names and values have to end up as strings.
                // value text normalisation and replacement may be recursive and a performance problem


                version(StrAllocation)
					attName = strAlloc_.alloc(scratch_.toArray);
				else
					attName = scratch_.idup;

                    
                if (attSpaceCt == 0)
                    doErrorCode(ParseErrorCode.MISSING_SPACE);
                

                getAttributeValue(scratch_);

                version(StrAllocation)
					attValue = strAlloc_.alloc(scratch_.toArray);
				else
					attValue =  scratch_.idup;
                if (normalizeAttributes)
                    attValue = this.attributeNormalize(attValue);
				r.attr.put(AttributeMap.BlockRec(attName, attValue));

                attCount++;
                break;
            }
        }
        assert(0);
    }
    protected int totalElementDepth()
    {
        return elementDepth_ + stackElementDepth_;
    }
    protected int elementDepth()
    {
        return elementDepth_;
    }

    protected final void checkEndElement()
    {
        int depth =  totalElementDepth();
        if (depth < 0)
            doErrorCode(ParseErrorCode.ELEMENT_NESTING);
        else if (depth == 0)
            state_ = PState.P_EPILOG;
        if (elementDepth_ < 0)
            doErrorCode(ParseErrorCode.ELEMENT_NESTING);
    }
    /// got a '</'  expecting a Name>
    protected final bool doEndTag(ref XmlReturn ret)
    {
        state_ = PState.P_DATA;
        dchar  test;

        if (getXmlName(tagScratch_))
        {
            // has to be end
            munchSpace();
            if (empty || front != '>')
                doErrorCode(ParseErrorCode.MISSING_END_BRACKET);
            markupDepth_--;
            elementDepth_--;
			if (isFragment)
			{
				pendingPop = true;
			}
			else
				popFront();
            checkEndElement();
            ret.type = XmlResult.TAG_END;
            version(TagStack)
            {
				if (tagStack_.length == 0)
					throwErrorCode(ParseErrorCode.ELEMENT_NESTING);

                lastCloseTag_ = tagStack_.back();
                tagStack_.popBack();
                if (lastCloseTag_ != tagScratch_.toArray)
                {
                    throwErrorCode(ParseErrorCode.ELEMENT_NESTING);
                }
                ret.scratch = lastCloseTag_;
            }
            else
            {
                ret.scratch = strAlloc_.alloc(tagScratch_.toArray);
            }
            itemCount++;
            return true;
        }
        doNotWellFormed("end tag expected");
        assert(0);
    }

    protected final bool doContent(ref XmlReturn ret)
    {
        content_.length = 0;
        bool  inCharData = false; // indicate that at least one character has been found
        bool  checkedCharData = false; // indicate already checked that character is allowed.
        //dchar  test = 0;

        bool returnTextContent()
        {
            ret.type = XmlResult.STR_TEXT;
            version(StrAllocation)
				ret.scratch = strAlloc_.alloc(content_.toArray);
			else
				ret.scratch = content_.idup;
            itemCount++;
            return true;
        }
        frontFilterOn();
        while (true)
        {
            if (empty)
            {
                if (totalElementDepth() > 0)
                    doErrorCode(ParseErrorCode.UNEXPECTED_END);
                if (inCharData)
                    return returnTextContent();
                else
                    return false;

            }
            switch(front)
            {
            case '<':
                markupDepth_++;
                frontFilterOff();
                popFront();
				if (empty)
					ThrowEmpty();


                switch(front)
                {
                case '/':
                    popFront();
                    if (inCharData)
                    {
                        state_ = PState.P_ENDTAG;
                        return returnTextContent();
                    }
                    return doEndTag(ret);
                case '?':
                    popFront();
                    if (inCharData)
                    {
                        state_ = PState.P_PROC_INST;
                        return returnTextContent();
                    }
                    return doProcessingInstruction(ret);
                case '!': // comment or cdata
                    popFront();
                    if (matchInput(CDATA_d))
                    {
                        squareDepth_ += 2;
                        if (inCharData)
                        {
                            state_ = PState.P_CDATA;
                            return returnTextContent();
                        }
                        return doCDATAContent(ret);
                    }
                    else if (matchInput(COMMENT_d))
                    {
                        if (inCharData)
                        {
                            state_ = PState.P_COMMENT;
                            return returnTextContent();
                        }
                        return doCommentContent(ret);
                    }
                    doErrorCode(ParseErrorCode.CDATA_COMMENT);
                    break;
                default:
                    // no pop front
                    if (isNameStartFn_(front) || isNameStartFifthEdition(front))
                    {
                        if (inCharData)
                        {
                            state_ = PState.P_TAG;
                            return returnTextContent();
                        }
                        return doStartTag(ret); // return this?
                    }
                    else
                    {
                        /// trick conformance issue
                        estk_.pushMsg(getErrorCodeMsg(ParseErrorCode.TAG_FORMAT),ParseError.fatal);
                        throw getBadCharError(front);
                    }
                } // end switch
                break; // end case '<'
            case '&':  // must be a reference
                popFront();
                if (!empty)
                {
                    uint radix;
                    if (front == '#')
                    {
                        dchar test = expectedCharRef(radix);
                        content_.put(test);
                        inCharData = true;
                        break;
                    }
                    else if (getXmlName(entityName_))
                    {
                        if (empty || front != ';')
                            doErrorCode(ParseErrorCode.BAD_ENTITY_REFERENCE);
                        popFront();
                        auto pc = entityName_.toArray in charEntity_;
                        if (pc !is null)
                        {
                            content_.put(*pc);
                            inCharData = true;
                            break;
                        }
                        // must be a special entity]
                        string ename = entityName_.idup;
                        decodeEntityReference(ename, false);
                        break;
                    }
                }
                doNotWellFormed("expected entity");
                break;
            case ']':
                if (matchInput(CDATA_END1_d))
                    doNotWellFormed("illegal CDATA end ]]>");
                goto default;
            default:
                if (front < 0x80)
                {
                    content_.put( cast(char)front);
                }
                else
                    content_.put(front);
                popFront();
                inCharData = true;
                break;
            } // end switch
        } // WHILE TRUE

        assert(0);
    }
    private final bool isCommentEnd()
    {
        if (empty || front != '-')
            return false;
        popFront();
        if (empty || front != '>')
            doNotWellFormed("Comment must not contain --");
        markupDepth_--;
        popFront();
        return true;
    }

    void decodeEntityReference(string ename, bool isAttribute)
    {
        EntityData ed;
        if (fetchEntityData(ename,isAttribute,ed))
        {
            auto evalue = ed.value_;
            if (evalue.length > 0)
                doPushContext(evalue,false,ed);
        }
    }


    final bool doCDATAContent(ref XmlReturn ret)
    {
        state_ = PState.P_DATA;
        scratch_.length = 0;
        frontFilterOn();
        while(!empty)
        {
            if ((front == ']') && isCDataEnd())
            {
                version(StrAllocation)
					ret.scratch = strAlloc_.alloc(scratch_.toArray);
				else
					ret.scratch = scratch_.idup;
                ret.type = XmlResult.STR_CDATA;
                itemCount++;
                return true;
            }
            else
            {
                scratch_.put(front);
                popFront();
            }
        }
        ThrowEmpty();
        return false;
    }

    // This is a potential speed bump. Especially if does not need normalizing.
    // Checks for raw < as error,  or a &#charEntity; or a &namedEntity;
    // So if no <, or & encountered, nothing needs to be done here.
    // May be this is most of the time, so a simple first check might be better.
    // Only looking for 7-bit characters, so raw access is fine.
    public string doAttributeNormalize(string src)
    {
        //TODO: any other standard entities not allowed either?
        void noLTChar()
        {
            doNotWellFormed("< not allowed in attribute value");
        }

        void noSingleAmp()
        {
             doNotWellFormed("single '&' not allowed");
        }

        version(speedBump)
        {
        intptr_t   speedBump = -1;
        PRE_SCAN:
        for(auto ix = 0; ix < src.length; ix++)
        {
            switch(src[ix])
            {
            case '<':
                noLTChar();
                break;
            case '&':
                 speedBump = ix;
                 break PRE_SCAN;
            default:
                break;
            }
        }
        if (speedBump == -1)
            return src;
        normalizeBuf_.length = 0;
        normalizeBuf_.put(src[0..speedBump]);
        src = src[speedBump..$];
        }
        else
        // do the worst.
        {
            Array!char  normalizeBuf_;
        }
        {
            doPushContext(src, true, null);
            scope(exit)
                doPopContext();

            //ctx_.allowEmpty(true);
            while(!empty)
            {
                if (isSpace(front))
                {
                    normalizeBuf_.put(' ');
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
                        normalizeBuf_.put(cref);
                        continue;
                    }
                    //string entityName;
                    // getXmlName uses scratch_
                    if (!getXmlName(entityName_) || !matchInput(';'))
                        noSingleAmp();

                    auto pc = entityName_.toArray in charEntity_;
                    if (pc is null)
                    {
                        string entityName = entityName_.idup;
                        decodeEntityReference(entityName, true);
                    }
                    else
                    {
                        normalizeBuf_.put(*pc);
                    }
                }
                else
                {
                    normalizeBuf_.put(front);
                    popFront();
                }
            }
			version(StrAllocation)
				return strAlloc_.alloc(normalizeBuf_.toArray);
			else
				return normalizeBuf_.idup;

        }
    }
    void doUnknownEntity(string ename)
    {
        string s = format("Unknown entity %s", ename);
        uint level = (isInParamEntity) ? ParseError.error : ParseError.fatal;

        throw prepareThrow(new ParseError(s, level));
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
                doNotWellFormed("illegal data at end document");
            }

            markupDepth_++;

            popFront();
            if (empty)
                doNotWellFormed("unmatched markup");
            test = front;
            popFront();
            switch(test)
            {
            case '?': // processing instruction or xmldecl
                return doProcessingInstruction(ret); // what else to do with PI'S?
            case '!':
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
    /** Recursively expand entity data to a fully expanded format.
    	Context already assumed to be set to entity data.
    	entityNameSet - names of entities expanded from first request.
    */
    bool doExpandEntityData(out string result, StringSet entityNameSet, out int refType)
    {


        uint	  radix;
        string	  ename;
        bool hitReference = false;

        //ParseInput src = sctx.in_;
        Array!(char) app;

        void putCharRef(dchar cref, uint radix)
        {

            app.put("&#");
            if (radix==16)
                app.put('x');
            app.put(to!string(cast(uint)cref,radix));
            app.put(';');
        }

        while (true)
        {
            if (empty)
                break;
            switch(front)
            {
            case '<':
                if (isPIStart())
                {
                    XmlReturn iret;
                    doProcessingInstruction(iret);
                    handleProcessInstruction(iret);// do something
                }
                else if (matchMarkupBegin(BCDATA_d))
                {
                    app.put("<![CDATA[");

                    bool hitEnd = false;

                    while(!empty) // this is to validate the CDATA section ends properly
                    {
                        if (front == '&')
                        {
                            popFront();
                            if (empty)
                                return false;
                            if (front == '#')
                            {
                                dchar cref = expectedCharRef(radix);
                                // and output it, still as character reference
                                putCharRef(cref,radix);

                            }
                            else
                            {
                                app.put('&');
                                expectEntityName(entityName_);
                                app.put(entityName_.toArray);
                                app.put(';');
                                //return push_error("raw & in entity value");
                            }
                        }
                        else if (isCDataEnd())
                        {
                            app.put("]]>");
                            hitEnd = true;
                            break;
                        }
                        else
                        {
                            app.put(front);
                            popFront();
                        }
                    }
                    if (empty && !hitEnd)
                    {
                        estk_.pushMsg("CData section did not terminate",ParseError.error);
                        return false;
                    }
                }
                else
                {
                    app.put(front);
                    popFront();

                }
                break;
            case '&':
                popFront();
                if (!empty && front=='#')
                {
                    dchar uc = expectedCharRef(radix);

                    if (uc == '&')
                    {
                        putCharRef(uc,radix);
                    }
                    else
                    {
                        app.put(uc);
                    }
                }
                else
                {
                    expectEntityName(entityName_);
                    auto pc = entityName_.toArray in charEntity_;

                    if (pc !is null)
                    {
                        app.put('&');
                        app.put(entityName_.toArray);
                        app.put(';');
                    }
                    else
                    {
                        int ref2;
                        string evalue;
                        ename = entityName_.idup;
                        if (!dtd_.lookupReference(this, ename, evalue, entityNameSet,ref2))
                        {
                            return false;
                        }
                        else
                        {
                            if (ref2 == RefTagType.NOTATION_REF)
                            {
                                // ignore this reference?
                            }
                            if (ref2 == RefTagType.SYSTEM_REF)
                                refType = RefTagType.SYSTEM_REF; // forced contamination
                            app.put(evalue);
                            hitReference = true;
                        }
                    }
                }
                break;
            default:
                app.put(front);
                popFront();
                break;
            } // end switch test
        } // end of data

        if (hitReference)
        {
            auto pp = contextPopper(this, app.idup);
            return doExpandEntityData(result, entityNameSet, refType);
        }
        result = app.unique;
        return true;
    }

    /** recursively replace entities in text
    return false if error
    if true, replaced.length > 0
    if no replacement, replaced == source.

    Replacement of parameter entities starting with % while in DTD only
    */
    bool textReplaceEntities(bool isInternal, string src, ref string opt, ref StringSet stk)
    {
        string evalue;
        auto pp = contextPopper(this,src);

        Array!char app;

        bool insertPEContent(const(char)[] peName)
        {

            /*if (isInternal)
            return ctx_.push_error("parameter entity in internal subset markup");
            */
            EntityData ed = dtd_.getParameterEntity(this,peName,stk,true);
            if (ed is null)
                return false;
            string content = ed.value_;
            app.put( content );
            return true;
        }

        while (!empty)
        {
            switch(front)
            {
            case '%':
                popFront();
                {
                    if (!empty && isNameStartFn_(front))
                    {
                        expectEntityName(entityName_);
                        if (!insertPEContent(entityName_.toArray))
                            throwParseError("Parameter entity replacement failed");
                    }
                }
                break;
            default:
                app.put( front );
                popFront();
                break;
            }

        }
        opt = app.unique;
        return true;
    }
    /// recursively replace entities in the attribute value
    void attributeTextReplace(string src, ref string value, uint callct = 0)
    {
        /// this is expensive, but so is validation
        auto ctx = contextPopper(this, src);

        Array!(char) p;

        while(!empty)
        {
            if (isSpace(front))
            {
                p.put(' ');
                popFront();
                continue;
            }
            else if (front == '<')
            {
                throwNotWellFormed("< not allowed in attribute value");
            }
            else if (front == '&')
            {
                popFront();
                if (empty)
                    throwNotWellFormed("single '&' not allowed");

                if (front == '#')
                {
                    uint radix;
                    dchar cref = expectedCharRef(radix);
                    p.put(cref);
                    continue;
                }
                //string entityName;

                if (!getXmlName(entityName_) || !matchInput(';'))
                    throwNotWellFormed("single '&' not allowed");

                auto pc = entityName_.toArray in charEntity_;
                if (pc !is null)
                {
                    p.put(*pc);
                }
                else
                {
                    EntityData ed;
                    string evalue;
                    string ename = entityName_.idup;
                    if (fetchEntityData(ename, true, ed))
                    {
                        if (!ed.isInternal_ && this.isStandalone_)
                            doNotWellFormed(text("External entity ",ename," referenced from standalone"));
                        attributeTextReplace(ed.value_, evalue, callct+1);
                        p.put(evalue);
                    }
                    else
                    {
                        // TODO: put the reference again? exception
                    }
                }
            }
            else
            {
                p.put(front);
                popFront();
            }
        }
        value = p.idup;
    }

    bool fetchEntityData(string ename, bool isAttribute, ref EntityData ed)
    {
        if (dtd_ is null)
            doUnknownEntity(ename);

        auto ge = dtd_.getEntity(ename);

        if (ge is null)
        {
            if (dtd_.undeclaredInvalid_ && !isAttribute)
            {
                if (validate_ )
                {
                    estk_.pushMsg(text("referenced undeclared entity ", ename),ParseError.invalid);
                    reportInvalid();
                }
                return false;
            }
            else
                doUnknownEntity(ename);
        }
        ed = ge;
        return true;
    }
}



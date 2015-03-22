/**

XML parsing according to the standard is expected to do a few ackward things
not easily handled with a simple string slicing approach.

This includes
Line ending normalisation, where 0xD and other special characters replaced with 0xA.
Source character preprocessing differs slightly between XML 1.0 and 1.1.

Handle the Byte-Order-Mark data in a file, and validate the declared encoding against it.
Handle DTD, defined text entities, replace character and standard entity.
Normalisation and text replacement that might occur in attribute values, and character data.


@Authors: Michael Rynn

@Date: Feb 2012
*/

module xmlp.xmlp.feeder;

import xmlp.xmlp.charinput;
import alt.zstring;
import std.string;
import xmlp.xmlp.subparse;
import xmlp.xmlp.error;
import std.conv;
import xmlp.xmlp.parseitem;
import xmlp.xmlp.xmlchar;
import std.utf;
import std.file, std.path;
import xmlp.xmlp.entitydata;

package enum CharFilter
{
    filterOff, filterOn, filterAlwaysOff
}


alias void delegate() EmptyNotify;
alias void delegate(Exception) ExceptionThrow;

/**
	Provides a source of filtered dchar from a raw XML source.
	Does not keep pointers to original source.
*/

class ParseSource
{
    dchar				front;
    bool				empty;

protected:
    size_t				nextpos_;
    size_t				lineNumber_;
    size_t				lineChar_;
    dchar				lastChar_;

    dchar[]				buffer_;
    Array!(dchar)	    stack_;

    DataFiller			dataFiller_;

    double				docVersion_ = 1.0;
    bool				isEndOfLine_;
	bool				isOlderXml_;

    CharFilter			doFilter_;
    ulong				srcRef_;

    //CharTestFn			isSourceFn;
    ExceptionThrow		exceptionDg;
    EmptyNotify			onEmptyDg;
    PrepareThrowDg		prepareExDg;

    EntityData          entity_;

    enum PState
    {
        P_PROLOG,
        P_TAG,
        P_ENDTAG,
        P_DATA,
        P_PROC_INST,
        P_COMMENT,
        P_CDATA,
        P_EPILOG,
        P_END
    }
    PState      state_;
public:
    /// Cannot get by without DataFiller.
    this(DataFiller df, double xmlver = 1.0)
    {
        empty = true;
        dataFiller_ = df;
		setXMLVersion(xmlver);
    }

    this()
    {
        empty = true;
    }

    @property bool isInParamEntity() const
    {
        return (entity_ !is null) && (entity_.etype_ == EntityType.Parameter);
    }
    @property bool isInGeneralEntity() const
    {
        return (entity_ !is null) && (entity_.etype_ == EntityType.General);
    }
    @property string entityName() const
    {
        return entity_ !is null ? entity_.name_ : null;
    }
    @property void notifyEmpty(EmptyNotify notify)
    {
        onEmptyDg = notify;
    }

    void initParse(DataFiller df, double xmlver = 1.0)
    {
        empty = true;
        dataFiller_ = df;
        stack_.length = 0;
        doFilter_ = CharFilter.filterOff;
        isEndOfLine_ = false;
        srcRef_ = 0;
        lineNumber_ = 0;
        lineChar_ = 0;
        lastChar_ = 0;
        nextpos_ = 0;
        buffer_.length = 0;
        setXMLVersion(xmlver);
		
    }
    /// set version for xml character filter

    /// get version for xml character filter
    void setXMLVersion(double val)
    {
        docVersion_ = val;
		isOlderXml_ = docVersion_ < 1.1;
    }
    @property final const double XMLVersion()
    {
        return docVersion_;
    }

    ulong sourceRef()
    {
        return srcRef_;
    }
    size_t lineNumber()
    {
        return lineNumber_;
    }
    size_t lineChar()
    {
        return lineChar_;
    }

    /// Push a single character in front of input stream
    final void pushFront(dchar c)
    {
        if (!empty)
            stack_.put(front);
        else
            empty = false;
        front = c;

    }
    /// push a bunch of UTF32 characters in front of everything else, in reverse.
    final void pushFront(const(dchar)[] s)
    {
        if (s.length == 0)
            return;

        if (!empty)
            stack_.put(front);
        else
            empty = false;
        auto slen = s.length;
        while (slen-- > 1)
            stack_.put(s[slen]);
        front = s[0];
    }

    /// replace front with next UTF32 character
    final void popFront()
    {
        if (stack_.length > 0)
        {
            front = stack_.back();
            stack_.popBack();
            return;
        }
        if (nextpos_ >= buffer_.length)
        {
            empty = !FetchMoreData();
            if (empty)
            {
                front = 0;
                if (onEmptyDg)
                    onEmptyDg();
                return;
            }
        }
        front = buffer_[nextpos_++]; // this should be enough

        if (doFilter_ != CharFilter.filterOn)
        {
            lineChar_++; // will be 1 off
            return;
        }
        // if turning on filterFront_ again, be sure to call filterFront as well
        filterFront();
    }

    /** turn source filtering back on, including the current front character */
    final void frontFilterOn()
    {
        if ((doFilter_ != CharFilter.filterOff) || empty)
            return;
        if (lineChar_ != 0)
            lineChar_--; // filter front will increment for current front
        doFilter_ = CharFilter.filterOn;
        filterFront();
    }

    /// stop any calls to frontFilterOn and frontFilterOff from working. Always off
    final void filterAlwaysOff()
    {
        doFilter_ = CharFilter.filterAlwaysOff;
    }

    /// Turn the filter off
    final void frontFilterOff()
    {
        if (doFilter_ != CharFilter.filterAlwaysOff)
            doFilter_ = CharFilter.filterOff;
    }

    /// format message for bad character
    static string badCharMsg(dchar c)
    {
        if (isValidDchar(c))
            return format("bad character 0x%x [%s]\n", c, c);
        else
            return format("invalid dchar 0x%x \n", c);
    }

    /** When not expecting special characters, such as XML names or markup,
    	check the front character for being valid source and do special substitution
    */
    final void filterFront()
    {
        if (isEndOfLine_)
        {
            isEndOfLine_ = false;
            lineNumber_++;
            lineChar_ = 0;

            if (lastChar_ == 0x0D)
            {
                lastChar_ = 0;
                switch(front)
                {
                case 0x0A:// (#xD #xA)  single #A for XML 1.0, skip this
                    popFront();
                    return;
                case 0x85: // (#xD #x85) single #A for XML 1.1, skip this
                    if (!isOlderXml_)
                        popFront();
                    return;
                case 0x2028: // put on the stack, as single #A for XML 1.1
                    if (!isOlderXml_)
                        front = 0x0A;
                    return;
                default:  // leave it as is.
                    break;
                }
            }
        }

        switch(front)
        {
        case 0x0D:
            lastChar_ = 0x0D;
            front = 0x0A;
        goto case 0x0A;
        case 0x0A:
            isEndOfLine_ = true;
            break;
        case 0x0085:
        case 0x2028:
            if (docVersion_ > 1.0)
            {
                front = 0x0A;
                isEndOfLine_ = true;
            }
            else
            {
                lineChar_++;
            }
            break;
        default:
            immutable c = front;
            immutable isSourceCharacter
                = (c >= 0x20) && (c < 0x7F) ? true
                  : (c < 0x20) ? ((c==0xA)||(c==0x9)||(c==0xD))
                  : (c <= 0xD7FF) ? isOlderXml_ || (c > 0x9F) || (c == 0x85)
                  : ((c >= 0xE000) && (c <= 0xFFFD)) || ((c >= 0x10000) && (c <= 0x10FFFF));

            if (!isSourceCharacter)
            {
                uint severity = ParseError.fatal;
                // Check position for crappy check for conformance tests on invalid BOM characters.
                if (lineChar_ == 0 && lineNumber_ == 0)
                    switch(front)
                    {
                    case 0xFFFE:
                    case 0xFEFF:
                        severity = ParseError.error;
                        goto default;
                    default:
                        break;
                    }
                Exception e = new ParseError(badCharMsg(front),severity);
                if (exceptionDg !is null)
                    exceptionDg(e);
                else
                    throw e;

            }
            lineChar_++;
            break;
        }

    }

    /// Get the first character into front, if its not there already
    final void pumpStart()
    {
        if (!empty)
            return;
        FetchMoreData();
        if (!empty)
            popFront();
		else
		{
            front = 0;
            if (onEmptyDg)
                 onEmptyDg();
		}
    }

    /// Get another buffer load of data.
    protected final bool FetchMoreData()
    {
        if (dataFiller_ is null || dataFiller_.isEOF())
            return false;
        if (dataFiller_.fillData(buffer_, srcRef_) && buffer_.length > 0)
        {
            empty = false;
            nextpos_ = 0;
            return true;
        }
        return false;
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

    /* If input matches the entire input, permanently advance,
       else stuff the saved characters in front
    */
    final bool matchInput(dstring match)
    {
        size_t lastmatch = 0; // track number of matched
        size_t mlen = match.length;
        dchar test;

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
            pushFront( match[0 .. lastmatch] );
            return false;
        }
    }
    /** simple parsing helper to eat up ordinary white space and return count.  */
    final uint munchSpace()
    {
        frontFilterOn();
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

    /** Return text up to the current position.
    	The size, start and range of result is unpredictable.
    	TODO: prefer to return string. Deprecate, use getErrorContext
    */

    dstring getPreContext(size_t range)
    {
        dstring result;
        auto slen = nextpos_;
        if (slen > range)
            slen = range;
        result.reserve(slen);
        size_t i = 0;
        auto spos = nextpos_ - slen;
        //check unicode sync
        static if (is(typeof(T)==char))
        {
            while (spos > 0)
            {
                if ((str_[spos] & 0xC0) == 0x80)
                    spos--;
                else
                    break;
            }
        }
        else static if (is(typeof(T)==wchar))
        {
            while (spos > 0)
            {
                wchar test = buffer_[spos];
                if (test >= 0xDC00 && test < 0xE000)
                    spos--;
                else
                    break;
            }
        }
        foreach(dchar c ; buffer_[spos .. nextpos_] )
        {
            result ~= c;
        }
        return result;
    }

    public string getErrorContext()
    {
        auto slen = buffer_.length;
        size_t spos = (nextpos_ > 40) ? nextpos_ - 40 : 0;
        size_t epos = spos + 80;
        if (epos > slen)
            epos = slen;
        return text(buffer_[spos..nextpos_],"|",buffer_[nextpos_..epos]);
    }
}


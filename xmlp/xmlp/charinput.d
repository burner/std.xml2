/**
	Part of std.xmlp package reimplementation of std.xml (cf.)
    DOM interface implementation for node base types.

Authors: Michael Rynn
Licence: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Distributed under the Boost Software License, Version 1.0.

Classes to recode input into a dchar buffer.

*/

module xmlp.xmlp.charinput;

import std.stdint;
import core.exception;
import xmlp.xmlp.inputencode;
import xmlp.xmlp.parseitem;
import xmlp.xmlp.error;
import std.stdint;
import std.utf;
import std.stream;
import std.string;
import std.conv;
import std.concurrency, std.socket;

import alt.zstring;

debug {
	import std.stdio;
}

/**
	A helper class to refill a buffer of InputStringRange
*/

class BufferFill(T)
{
protected:
    bool eof_; // Just had LAST FILL!
public:
    this()
    {
        eof_ = true;
    }

    @property bool isEOF()
    {
        return eof_;
    }
    bool setEncoding(string encoding)
    {
        return false;
    }
    bool setBufferSize(uint bsize)
    {
        return false;
    }
    bool fillData(ref T[] buffer, ref ulong sourceRef)
    {
        return false;
    }
}

/**

Data is provided from any source by the $(D MoreDataDgate).
An optional $(I EmptyNotify) delegate is called if the BufferFill!(T) returns false.
Data can be pushed back onto an input stack.
The input stack is used up first before the primary source.
This implementation takes the step of having popFront set the
values of both front_ and empty_.

The method pumpStart exists to get the stream
going for the first time. The empty property will be true unless pumpStart is called.

This range is primed by setting arraySource, or dataSource property,
and then calling pumpStart. If the input is already exhausted, then empty will
still become true after the pumpStart.

InputCharRange mostly ignores UTF encoding.


*/

class InputCharRange(T)
{
    /// Delegate to refill the buffer with data,
    alias BufferFill!(T)	DataFiller;
    /// Delegate to notify when empty becomes true.
    alias void delegate() EmptyNotify;

    protected
    {
        Array!T				stack_; // push back
        bool				empty_;
        T					front_;

        T[]					str_;  // alias of a buffer to be filled by a delegate
        size_t				nextpos_; // index into string

        DataFiller	        df_; // buffer filler
        EmptyNotify			onEmpty_;
        ulong				srcRef_;  // original source reference, if any

        /// push stack character without changing value of front_
        void pushInternalStack(T c)
        {
            stack_.put(c);
        }
    }
	
	version(NoGarbageCollection)
	{
		~this()
		{
			delete df_;
		}

	}

    /// return empty property of InputRange
    @property
    public const final bool empty()
    {
        return empty_;
    }

    /// return front property of f
    @property
    public const final T front()
    {
        return front_;
    }
    protected
    {
        bool FetchMoreData(bool firstPop = false)
        in {
            assert(nextpos_ >= str_.length,"FetchMoreData buffer not empty");
        }
        body {
            if (df_ is null || df_.isEOF())
                return false;
            if (df_.fillData(str_, srcRef_) && str_.length > 0)
            {
                empty_ = false;
                // popFront call is bad, since this was likely called from a popFront.
                // however, if this is the very first character, called from pumpStart
                // then have to simulate popFront.
                if (firstPop)
                    popFront();
                else
                {
                    front_ = str_[0];
                    nextpos_ = 1;
                }
                return true;
            }
            return false;
        }
    }
public:
    this()
    {
        empty_ = true;
    }
    this( string s)
    {

    }
    /// notifyEmpty read property
    @property EmptyNotify notifyEmpty()
    {
        return onEmpty_;
    }
    /// notifyEmpty write property
    @property void notifyEmpty(EmptyNotify notify)
    {
        onEmpty_ = notify;
    }
    /// indicate position of datastream in original source
    @property final ulong sourceReference()
    {
        return srcRef_ + nextpos_;
    }

    /// Number of bytes per array item
    @property final uint sourceUnit()
    {
        return T.sizeof;
    }

    // subtract this from sourceReference to get the position of the buffer start
    @property final auto sourceOffset()
    {
        return nextpos_;
    }

    /// After setting this, require call to pumpStart
    @property void arraySource(T[] data)
    {
        str_ = data;
        empty_ = true;
        srcRef_ = 0;
        nextpos_ = 0;
    }

    /// After setting this, require call to pumpStart
    @property void dataSource(DataFiller df)
    {
        df_ = df;
        empty_ = true;
        srcRef_ = 0;
        nextpos_ = 0;
    }

    /**
    	Only does anything if empty is already set to true, which
    	can be from setting the dataSource property. It will only then reset empty,
    	and try to prime the input with a popFront.
    	Returns !empty.
    */

    bool pumpStart()
    {
        if (!empty_)
            return true;

        if (df_ !is null)
        {
            empty_ = !FetchMoreData(true);
        }
        else
        {
            empty_ = (str_.length > 0);
            nextpos_ = 0;
            if (!empty)
                popFront();
        }
        return !empty_;
    }



    /// Push a single character in front of input stream
    final void pushFront(T c)
    {
        if (!empty_)
        {
            stack_.put(front_);
        }
        front_ = c;
        empty_ = false;
    }
    /// push a bunch of characters back in front of stream
    final void pushFront(const(T)[] s)
    {
        if (s.length == 0)
            return;

        if (!empty_)
        {
            // normal case
            stack_.put(front_);
        }
        auto slen = s.length;
        while (slen-- > 1)
            stack_.put(s[slen]);
        front_ = s[0];
        empty_ = false;
    }

    /// push a bunch of characters back in front of stream
final void convertPushFront(U : U[])(const(U)[] s)
    if (!is(typeof(U) == typeof(T)))
    {
        pushFront(to!(const(T)[])(s));
    }

    /** InputRange method to bring the next character to front.
    	Checks internal stack first, and if empty uses primary buffer.
    */
    void popFront()
    {
        if (empty_)
            throw new RangeError("popFront when empty",__LINE__);
        if (stack_.length > 0)
        {
            front_ = stack_.back();
            stack_.popBack();
            return;
        }
        if (nextpos_ < str_.length)
        {
            front_ = str_[nextpos_++];
        }
        else
        {
            empty_ = !FetchMoreData();
            if (empty_)
            {
                front_ = 0;
                if (onEmpty_)
                    onEmpty_();
            }
        }
    }
    /// Return the front character if not empty, no state change
    final const bool peek(ref T next)
    {
        if (!empty_)
        {
            next = front_;
            return true;
        }
        return false;
    }
    /// Return the front character if not empty, and call popFront
    final bool pull(ref T next)
    {
        if (!empty_)
        {
            next = front_;
            popFront();
            return true;
        }
        return false;
    }
    /** Change the number of characters returned at a time.
        It may or may not take effect only after refill.
    	For xml documents a small buffer size is used until the encoding
    	has been established.
    */
    final bool setBufferSize(uint bsize)
    {
        if (df_ !is null)
            return df_.setBufferSize(bsize);
        else
            return false;
    }
    /** Change the character encoding of the underlying datastream.
    	It may or may not take effect only after refill.
    */

    final bool setEncoding(string encoding)
    {
        if (df_ !is null)
            return df_.setEncoding(encoding);
        else
            return false;
    }

}

/**
    Can pushFront dchar or dchar[] onto a stack, which is emptied first.
    popFront is done in constructor, so that empty and front, both mandatory calls, are as fast as possible.
    Property index points to position of front in data string, only if stack_ was empty on last popFront.
*/

struct ParseInputRange(T)
{
    const(T)[]			data;
    uintptr_t           index_;
    uintptr_t			pos = 0;
    dchar				front;
    bool				empty;
    Array!dchar	stack_;

    // refers to front if stack_ was empty last popFront
    @property uintptr_t index()
    {
        return index_;
    }

    // refers to front if stack_ was empty last popFront
    @property uintptr_t nextIndex()
    {
        return pos;
    }
    this(const(T)[] s)
    {
        data = s;
        popFront();
    }

    void pushFront(dchar c)
    {
        if (!empty)
            stack_.put(front);
        else
            empty = false;
        front = c;

    }
    /// push a bunch of UTF32 characters in front of everything else, in reverse.
    void pushFront(const(dchar)[] s)
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

    void popFront()
    {
        if (stack_.length > 0)
        {
            front = stack_.back();
			stack_.popBack();
            return;
        }
        if (pos < data.length)
        {
            index_ = pos;
            static if (is(T==char) || is(T==wchar))
            {
                front = decode(data,pos);
            }
            else
            {
                front = data[pos++];
            }
        }
        else {
            index_ = pos;
            empty = true;
        }
    }
}

/**
	Take as input source a D string
*/
class SliceFill(T) :  BufferFill!(dchar)
{
protected:
    const(T)[]	src_;
    size_t		usedup_;

    enum {INTERNAL_BUF = 2048};

public:
    override bool fillData(ref dchar[] data, ref ulong sref)
    {

        auto slen = src_.length;
        size_t maxlen;
        sref = usedup_;
        size_t pos = 0;

        if (data.length == 0)
        {
            maxlen = (slen < INTERNAL_BUF) ? slen : INTERNAL_BUF;
            data.length = maxlen;
        }
        else
        {
            maxlen = data.length;
        }

        if (slen == 0)
        {
            return false;
        }

        static if (is(T==dchar))
        {
            // unlikely
            pos = (maxlen < slen) ? maxlen : slen;
            data[0..pos] = src_[0..pos];
            data.length = k;
            src_ = src_[pos..$];

        }
        else static if (is(T==wchar))
        {

            data.length = decode_wchar(src_, data, pos);
            src_ = src_[pos..$];

        }
        else static if (is(T==char))
        {
            data.length = decode_char(src_, data, pos);
            src_ = src_[pos..$];
        }
        usedup_ += pos;
        if (src_.length == 0)
            eof_ = true;
        return (data.length > 0);
    }
    this(const(T)[] s)
    {
        super();
        src_ = s;
        eof_ = (s.length == 0);
    }
}



class StreamFill(T) :  BufferFill!(T)
{
    Stream  s_; // InputStream does not have seek
    ubyte[] data_; // Standard stream is a bastard with endian swapping.

    enum { INTERNAL_BUF = 4096}

    override bool fillData(ref T[] fillme, ref ulong refPos)
    {
        if (data_ is null)
        {
            data_ = new ubyte[INTERNAL_BUF];
        }
        refPos = s_.position / T.sizeof; // reference in character units

        size_t didRead = s_.read(data_);
        if (didRead > 0)
        {
            fillme = (cast(T*) data_.ptr)[0..didRead / T.sizeof];
            return true;
        }
        return false;
    }
    this(Stream ins)
    {
        super();
        s_ = ins;
        eof_ = false;
    }
}

/// Connection of raw streams (data buffer fillers) to decoding InputRange

alias	StreamFill!(char) CharFiller;
alias	StreamFill!(wchar)  WCharFiller;
alias	StreamFill!(dchar)  DCharFiller;

alias	InputCharRange!(char) CharIR;
alias	InputCharRange!(wchar) WCharIR;
alias	InputCharRange!(dchar) DCharIR;

alias RecodeChar!(CharIR)	Recode8;
alias RecodeWChar!(WCharIR)	Recode16;
alias RecodeDChar!(DCharIR)	Recode32;

/// Big complicated class to provide a single interface to different kinds of encoded inputs.

class XmlStreamFiller :  BufferFill!(dchar)
{
    // inherit ParseInput so can use buffer and pointer to member function type

    Stream		rawStream;

    uint		nextBufferSize_;
    bool        checkedBom_;
    uint	    selector_;
    string		encoding_;
    ByteOrderMark	bom_;
	Array!dchar	buffer_;

    // only one of these pairs of input ranges and decoders will be selected.

    CharIR  cir_;
    Recode8.RecodeFunc charDo_;


    WCharIR wir_;
    Recode16.RecodeFunc wcharDo_;


    DCharIR dir_;
    Recode32.RecodeFunc dcharDo_;

    enum { SMALL_BUFFER_SIZE = 4, LARGE_BUFFER_SIZE = 1024};

    void init()
    {
        checkedBom_ = false;
        eof_ = false;
        nextBufferSize_ = SMALL_BUFFER_SIZE;
        selector_ = 0; // input character size
    }

public:
    this(Stream s)
    {
        rawStream = s;
        init();
    }

	version(NoGarbageCollection)
	{
		~this()
		{
			rawStream.close();
			if (cir_)
				delete cir_;
			if (wir_)
				delete wir_;
			if (dir_)
				delete dir_;
		}
	}

    @property final uint charBytes()
    {
        return selector_;
    }

    /// passed a buffer from caller

    override bool fillData(ref dchar[] buffer, ref ulong posRef)
    {
        if (!checkedBom_)
        {
            checkedBom_ = true;
            if (!initStream())
                return false;
            // use the decode to fill the buffer

        }
        // now get  characters.
        if (buffer.length != nextBufferSize_)
            buffer.length = nextBufferSize_;

        switch(selector_)
        {
        case 1:
            return fillCharData(buffer,posRef);

        case 2:
            return fillWCharData(buffer,posRef);

        case 4:
            return fillDCharData(buffer,posRef);

        default:
            break;
        }
        return false;
    }
    /// return the encoding name
    string getEncoding()
    {
        return bom_.key.codeName;
    }
    /// Setup the correct conversion function for the encoding, check for source BOM compatibility.
    override bool setEncoding(string encoding)
    {
        if (bom_ !is null) // always true?
        {
            string uenc = encoding.toUpper();
            // a switch in coding must be compatible with current bom?
            if (uenc == bom_.key.codeName)
            {
                return true;
            }
            else
            {
                if (bom_ != ByteOrderRegistry.noMark)
                {
                    throw encodingInvalid(bom_.key.toString(), encoding);
                }
            }
        }

        switch(selector_)
        {
        case 1:
        {
            auto test1 = Recode8.getRecodeFunc(encoding);
            if (test1 is null)
                throw encodingNotFound(selector_,encoding);
            charDo_ = test1;
        }
        break;
        case 2:
        {
            auto test2 = Recode16.getRecodeFunc(encoding);
            if (test2 is null)
                throw encodingNotFound(selector_,encoding);
            wcharDo_ = test2;
        }
        break;
        case 4:
        {
            auto test4 = Recode32.getRecodeFunc(encoding);
            if (test4 is null)
                throw encodingNotFound(selector_,encoding);
            dcharDo_ = test4;
        }
        break;
        default:
            return false;
        }
        return true;
    }

    /// when the buffer is next empty, it will adopt the new size.
    override bool setBufferSize(uint bsize)
    {
        nextBufferSize_ = bsize;
        return true;
    }

private:
    /**
     * Start reading the stream, find out BOM and encoding, start decoding
     * into a stream of dchar. Return true if successful and data exists.
     **/
    bool   initStream()
    {
        Array!ubyte preload;

        preload.reserve(8);
        bool eofFlag_ = false;

        bom_ = readStreamBOM(rawStream, preload, eofFlag_);
        if (eofFlag_ && (preload.length == 0))
        {
            return false;
        }

        encoding_ = bom_.key.toString();
        selector_ = bom_.charSize;

        switch (selector_)
        {
        case 1:
        {
            CharFiller fill = new CharFiller(rawStream);
            cir_  = new CharIR();
            cir_.dataSource(fill);
            cir_.pumpStart();
            charDo_ = Recode8.getRecodeFunc(encoding_);

            if (charDo_ is null)
                return false;
            const auto pct = preload.length;
            if (pct > 0)
            {
                for(uint k = 0; k < pct; k++)
                    cir_.pushFront(preload[k]);
            }
        }
        break;

        case 2:
        {
            auto wfill = new WCharFiller(rawStream);
            wir_ = new WCharIR();
            wir_.dataSource(wfill);
            wir_.pumpStart();

            wcharDo_ = Recode16.getRecodeFunc(encoding_);
            if (wcharDo_ is null)
                return false;
            if (preload.length > 0)
            {
                wchar[]	  buf;
                wswapchar sbytes;
                for(uintptr_t k = 0; k+1 < preload.length; k += 2)
                {
                    sbytes.c.c0 = preload[k];
                    sbytes.c.c1 = preload[k+1];
                    wir_.pushFront(sbytes.w0);
                }
            }
        }
        break;
        case 4:
        {
            auto dfill = new DCharFiller(rawStream);//DCharDecode
            dir_ = new DCharIR();
            dir_.dataSource(dfill);
            dir_.pumpStart();

            dcharDo_ = Recode32.getRecodeFunc(encoding_);
            if (dcharDo_ is null)
                return false;

            if (preload.length > 0)
            {
                dchar[] buf;
                dswapchar sbytes;

                for(uintptr_t k = 0; k+3 < preload.length; k += 4)
                {
                    sbytes.c.c0 = preload[k];
                    sbytes.c.c1 = preload[k+1];
                    sbytes.c.c2 = preload[k+2];
                    sbytes.c.c3 = preload[k+3];
                    dir_.pushFront(sbytes.d0);
                }
            }
        }
        break;

        default:
            return false;
        }
        return true;
    }


    bool fillCharData(ref dchar[] buffer, ref ulong posRef)
    {
        posRef = cir_.sourceReference();
        uint i;
        try
        {
            for(i = 0; i < buffer.length; i++)
            {
                if (!charDo_(cir_,buffer[i]))
                {
                    if (cir_.empty && (i > 0))
                    {
                        buffer.length = i;
                        eof_ = true;
                        return true;
                    }
                    return false;
                }
            }
        }
        catch (CharSequenceError ex)
        {
            throw recodeFailed(posRef + i, ex.toString());
        }
        return true;
    }

    bool fillWCharData(ref dchar[] buffer, ref ulong posRef)
    {
        posRef = wir_.sourceReference();
        for(uintptr_t i = 0; i < buffer.length; i++)
        {
            if (!wcharDo_(wir_ ,buffer[i]))
            {
                if (wir_.empty && (i > 0))
                {
                    buffer.length = i;
                    eof_ = true;
                    return true;
                }
                return false;
            }
        }
        return true;
    }
    bool fillDCharData(ref dchar[] buffer, ref ulong posRef)
    {
        posRef = dir_.sourceReference();
        for(uintptr_t i = 0; i < buffer.length; i++)
        {
            if (!dcharDo_(dir_,buffer[i]))
            {
                if (dir_.empty && (i > 0))
                {
                    buffer.length = i;
                    return true;
                }
                return false;
            } 
        }
        return true;
    }

}

/// This needs to be on a thread (see std.concurrency receive documentation)
/// the receive blocks until sent a string.  Designed for server based on listener.d example


class AsyncFill : BufferFill!(dchar)
{
	Array!char	source;
	bool		isResidual;
	ulong		ct;

	this()
	{
		eof_ = false;
	}

	bool getMore()
	{
		/+
		2.059 compile errors
		ulong oldCount = ct;
		receive( (string s) 
				{ 
					source.put(s);
					ct += s.length;
				} 
				);
		return ct > oldCount;
		+/
		return false;
	}

    override bool fillData(ref dchar[] buffer, ref ulong posRef)
    {
		posRef = ct;
		for (;;)
		{
			if (source.length == 0 || isResidual)
			{
				if (!getMore())
				{
					eof_ = true;
					return false;
				}
			}
			if (buffer.length < source.length)
				buffer.length = source.length;
			auto temp = source.toArray;
			uintptr_t ix = 0;
			buffer.length = decode_char(temp,buffer,ix);
			if (ix > 0)
			{
				// source consumed
				// more residual to front, and reset length
				if (ix < temp.length)
				{
					auto newLength = temp.length-ix;
					temp[0..newLength] = temp[ix..$];
					source.length = newLength;
					isResidual = true;
				}
				else {
					source.length = 0;
					isResidual = false;
				}
			}
			if (buffer.length > 0)
				return true;
		}
	}
}

/// get whats next available from a socket. Reading from a SocketStream seems an unncessary wrapper
class SocketFill : AsyncFill {
	Socket	sock_;

	this(Socket s)
	{
		sock_ = s;
	}
	
	override bool getMore()
	{
		ulong oldCount = ct;
		char[1024] cbuf;

		intptr_t read = sock_.receive(cbuf); // this blocks if no data
		if (Socket.ERROR == read)
		{
			sock_.close(); // release socket resources now
			debug writeln("Socket Error closed ", read);
			throw new ParseError("Socket error", ParseError.error);
		}
		else if (0 == read)
		{
			eof_ = true;
			string err_message;
			try
			{
				// if the connection closed due to an error, remoteAddress() could fail
				err_message = format("Connection from %s closed.", sock_.toString());
			}
			catch (SocketException)
			{
				err_message = "Connection closed.";
			}
			debug writeln("Socket error: ",err_message);
			throw new ParseError(err_message, ParseError.error);
		}
		else {
			debug writeln("read: ", cbuf[0..read]);
			source.put(cbuf[0..read]);
			ct += read;
		}
		return ct > oldCount;
	}
}

/// generate ParseError at an input positions
Exception recodeFailed(ulong position, string msg)
{
    return new ParseError(text("Recode function failed at position ", position, ". ", msg), ParseError.error);
}


/// generate ParseError for incompatible encoding
Exception encodingIncompatible(string name, uint selector)
{
    return new ParseError(format("Encoding %s is incompatible with source size of %s bytes", name, selector), ParseError.fatal);
}

/** Failed to find an encoding function for the character size being used.
 Check for other character sizes, if found, throw incompatible, if not, throw not found.
 Wrong encoding is not well formed, not known is an error.
*/

Exception encodingNotFound(uint selector, string name)
{
    string found;
    if (selector != 1)
    {
        auto test1 = Recode8.getRecodeFunc(name);
        if (test1 != null)
        {
            return encodingIncompatible(name,selector);
        }
    }
    if (selector != 2)
    {
        auto test2 = Recode16.getRecodeFunc(name);
        if (test2 != null)
        {
            return encodingIncompatible(name,selector);
        }
    }
    if (selector != 4)
    {
        auto test4 = Recode32.getRecodeFunc(name);
        if (test4 != null)
        {
            return encodingIncompatible(name,selector);
        }
    }
    return new ParseError(text("Encoding not found	",name, " bytes ",selector), ParseError.error);
}

/// Encoding is invalid for BOM.
Exception encodingInvalid(string bomName, string encName)
{
    return new ParseError(text("Encoding ambiguity with byte order mark ",bomName, " encoding ",encName), ParseError.invalid);
}

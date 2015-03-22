/**

Part of xmlp.xmlp package reimplementation of std.xml.

Low level XML input and syntax parsing.

Authors: Michael Rynn
Licence: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Distributed under the Boost Software License, Version 1.0.

Objects derived from Exception. Some common messages.  ErrorStack to collect errors.

*/
module xmlp.xmlp.error;

import std.conv;
import std.string;

/// Error codes expected by DOM
enum
{
    XML_ERROR_OK = 0,
    XML_ERROR_INVALID = 1,
    XML_ERROR_ERROR = 2,
    XML_ERROR_FATAL = 3
};

/// Common messages that have a string lookup.
enum ParseErrorCode
{
    UNEXPECTED_END,
    TAG_FORMAT,
    MISSING_QUOTE,
    EXPECTED_ATTRIBUTE,
    BAD_CHARACTER,
    MISSING_SPACE,
    DUPLICATE_ATTRIBUTE,
    ELEMENT_NESTING,
    CDATA_COMMENT,
    BAD_ENTITY_REFERENCE,
    MISSING_END_BRACKET,
    EXPECTED_NAME,
    CONTEXT_STACK,
};

/// Return a string for the error code

string getErrorCodeMsg(int code)
{
    switch(code)
    {
    case ParseErrorCode.UNEXPECTED_END:
        return "Unexpected end to parse source";
    case ParseErrorCode.TAG_FORMAT:
        return "Tag format error";
    case ParseErrorCode.MISSING_QUOTE:
        return "Missing quote";
    case ParseErrorCode.EXPECTED_ATTRIBUTE:
        return "Attribute value expected";
    case ParseErrorCode.BAD_CHARACTER:
        return "Bad character value";
    case ParseErrorCode.MISSING_SPACE:
        return "Missing space character";
    case ParseErrorCode.DUPLICATE_ATTRIBUTE:
        return "Duplicate attribute";
    case ParseErrorCode.ELEMENT_NESTING:
        return "Element nesting error";
    case ParseErrorCode.CDATA_COMMENT:
        return "Expected CDATA or Comment";
    case ParseErrorCode.BAD_ENTITY_REFERENCE:
        return "Expected entity reference";
    case ParseErrorCode.MISSING_END_BRACKET:
        return "Missing end >";
    case ParseErrorCode.EXPECTED_NAME:
        return "Expected name";
    case ParseErrorCode.CONTEXT_STACK:
        return "Pop on empty context stack";
    default:
        break;
    }
    return "Unknown error code";
}
/**
Base class for parser exceptions, has a severity value
to distinguish some error types.
*/
class ParseError : Exception
{
    uint severity;
    int code_;

    enum { noError, invalid, error, fatal };

    this(int code, uint level = fatal)
    {
        code_ = code;
        severity = level;
        super(getErrorCodeMsg(code_));
    }
    this(string s, uint level = fatal)
    {
        severity = level;
        super(s);
    }
}

/// Accumulate errors to show context

class ErrorStack
{
protected:
    uint	errorLevel;

    string[]	msgStack;
public:
    /// OK = 0
    @property final uint errorStatus()
    {
        return errorLevel;
    }

    /// the stacked messages
    string[]	messages()
    {
        return msgStack;
    }

    /// set and remember worst error level
    @property final void errorStatus(uint level)
    {
        if (level > errorLevel)
            errorLevel = level;
    }
    /// clear everything
    void clear()
    {
        msgStack.length = 0;
        errorLevel = 0;
    }

    /// add a message, and its severity level
    uint pushMsg(string msg, uint level = 0)
    {
        msgStack ~= msg;
        if (level > errorLevel)
            errorLevel = level;
        return errorLevel;
    }

    /// return all the messages as single string with linefeeds
    override string toString()
    {
        size_t bufsize = 0;
        auto mlen = msgStack.length;
        for(uint  k = 0; k < mlen; k++)
        {
            bufsize += msgStack[k].length + 1;
        }

        string result;

        if (bufsize > 0)
        {
            result.reserve(bufsize);
            for(uint  k = 0; k < mlen; k++)
            {
                result ~= msgStack[k];
                result ~= '\n';
            }
        }
        return result;
    }
};



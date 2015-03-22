/**


Shared definitions, structures and interface for xmlp.xmlp

Defines XmlReturn, a structure used by all parser modules to return fragments of XML.
Defines IXMLParser.

Authors: Michael Rynn
Licence: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Distributed under the Boost Software License, Version 1.0.

*/

module xmlp.xmlp.subparse;

public import std.stdint;
import xmlp.xmlp.inputencode;
import xmlp.xmlp.charinput;
import xmlp.xmlp.error;
import xmlp.xmlp.xmlchar;
import xmlp.xmlp.parseitem;
import std.conv;
import std.string;
import std.array;
import std.stream;
import core.stdc.string;
import std.range;
import std.exception;
import std.utf;
import xmlp.xmlp.dtdtype;
import xmlp.xmlp.entitydata;
import std.variant;

static if (__VERSION__ <= 2053)
{
    import std.ctype;
    alias isalpha isAlpha;
    alias isalnum isAlphaNum;
}
else
{
    import std.ascii;
}

static const dstring DASH2_d = "--";
static const dstring BCDATA_d = "<![CDATA[";
static const dstring BCOMMENT_d = "<!--";
static const dstring CDATA_d = "[CDATA[";
static const dstring COMMENT_d = "--";
static const dstring CDATA_END1_d = "]>";

static const dstring VERSION_d = "version";
static const dstring ENCODING_d = "encoding";
static const dstring STANDALONE_d = "standalone";
static const dstring DOCTYPE_d = "DOCTYPE";

/// Decoders for char using a InputRange
/// with combined pull (!empty, front, popFront)

// these either return a character or tell the caller it cannot be done.
alias bool delegate(ref char c)  Char8pull;
alias bool delegate(ref wchar c) Char16pull;
alias bool delegate(ref dchar c) Char32pull;

// RecodeDgFn.  Each function type uses the corresponding delegate
alias bool function(Char8pull src, ref dchar c) Recode8Fn;
alias bool function(Char16pull src, ref dchar c) Recode16Fn;
alias bool function(Char32pull src, ref dchar c) Recode32Fn;

/** Internal types used in the parser.
    This is for performance testing, to see how much internal conversions matter
	Final outputs will still be string
*/
//version = XMLSTR_INTERNAL;
// To check speed of using dstring internally.
// Its about 20% slower.


/// Refers to test functions in xmlp.xmlp.xmlChar

alias   bool function(dchar c) pure	CharTestFn;

/** setParameter names. Results of setParameter method will vary with parser.

  xmlAttributeNormalize :
 Turn off or on, attribute character decoding, in the low level parser,
as some handlers may want to handle this themselves.

  xmlCharFilter : Turn off white space and unicode space character normalization, and other checks.

xmlNamespaces : Parser may be more namespace aware.

xmlFragment : Parser returns without first checking for content of document node.
*/

enum string xmlAttributeNormalize = "attribute-normalize";
enum string xmlCharFilter = "char-filter";
enum string xmlNamespaces = "namespaces";
enum string xmlFragment = "fragment";


/** Split string on the first ':'.
 *  Return number of ':' found.
 *  If no first splitting ':' found return nmSpace = "", local = name.
 *  If returns 1, and nmSpace.length is 0, then first character was :
 *  if returns 1, and local.length is 0, then last character was :
**/
intptr_t splitNameSpace(string name, out string nmSpace, out string local)
{
    intptr_t sepct = 0;

    auto npos = indexOf(name, ':');

    if (npos >= 0)
    {
        sepct++;
        nmSpace = name[0 .. npos];
        local = name[npos+1 .. $];
        if (local.length > 0)
        {
            string temp = local;
            npos = indexOf(temp,':');
            if (npos >= 0)
            {
                sepct++;  // 2 is already too many
                //temp = temp[npos+1 .. $];
                //npos = indexOf(temp,':');
            }
        }
    }
    else
    {
        local = name;
    }
    return sepct;
}


/// check that the URI begins with a scheme name
/// scheme        = alpha *( alpha | digit | "+" | "-" | "." )


pure bool isURIScheme(string scheme)
{
    if (scheme.length == 0)
        return false;
    bool firstChar = true;
    foreach(dchar nc ; scheme)
    {
        if (firstChar)
        {
            firstChar = false;
            if (!isAlpha(nc))
                return false;
        }
        else
        {
            if (!isAlphaNum(nc))
            {
                switch(nc)
                {
                case '+':
                case '-':
                case '.':
                    break;
                default:
                    return false;
                }
            }
        }
    }
    return true;
}

/// name corresponds to some sort of URL
bool isNameSpaceURI(string name)
{
    string scheme, restof;

    auto sepct = splitNameSpace(name, scheme, restof);
    if (sepct == 0)
        return false;
    // scheme names are presumed to be ASCII
    if (!isURIScheme(scheme))
        return false;

    // check that the restof is ASCII
    foreach(dchar nc ; restof)
    {
        if (nc > 0x7F)
        {
            return false;
        }
    }
    return true;
}

/// more relaxed definition of IRI
bool isNameSpaceIRI(string name)
{
    string scheme, restof;

    auto sepct = splitNameSpace(name, scheme, restof);
    if (sepct == 0)
        return false;
    // scheme names are presumed to be ASCII
    if (!isURIScheme(scheme))
        return false;

    // TODO: no restrictions yet on restof

    return true;
}

version (CHAR_ENTITY_MAP)
{
    alias dchar[string] stdEntityMap;

/// return a fresh character map filled with standard Xml entities
    stdEntityMap stdCharEntityMap()
    {
        stdEntityMap map;

        map["lt"] = '<';
        map["gt"] = '>';
        map["amp"] = '&';
        map["quot"] = '\"';
        map["apos"] = '\'';

        return map;
    }

}
else
{
    alias StringMap StdEntityMap;

    /// return a fresh character map filled with standard Xml entities
    StdEntityMap stdCharEntityMap()
    {
        StdEntityMap map;

        map["lt"] = "<";
        map["gt"] = ">";
        map["amp"] = "&";
        map["quot"] = "\"";
        map["apos"] = "\'";

        return map;
    }


}

/** With different kinds of parser, maybe some things can be shared, even though
	some methods will be incommensurable. Added for DTDValidate usage.

	Parsers to support
		1. returns alias of transient char[] buffers,   DataFiller, fast
		2. returns alias of string ,  direct string source, faster still

	A factory method is too difficult?
*/
alias BufferFill!(dchar) DataFiller;

/// ParseReturn may be hard coded to use string in future,
/// as mutable char is being abandoned

/// slightly useful, non-specific parser location data
struct SourceRef
{
    intptr_t		charsOffset; // position in stream of source haracters. Absolute or encoding dependent?
    intptr_t		lineNumber; // encoding dependent
    intptr_t        colNumber;	 // encoding dependent
};

/// Delegate for handling exceptions before they are throw.
alias ParseError delegate(ParseError ex) PrepareThrowDg;
alias void delegate(string msg) ReportInvalidDg;
alias void delegate(string target, string data) ProcessingInstructionDg;


public interface IXMLParser 
{
    /// setup
    void initParse(); // sad hack

    /// Return parse detail
    bool parse(ref XmlReturn ret);


    /// return a ParseError Exception object with message


    /// parser will expect name spaces
    bool namespaces() const;
    void namespaces(bool doNameSpaces);


    /// Return current entity data or null
    EntityData entityContext();

    /// Set current entity context
    void entityContext(EntityData val);

    /// Get Object to push errors onto
    ErrorStack getErrorStack();
    /// Document did not declare standalone="no"
    bool isStandalone() const;

    /// If parse expects to validate
    bool validate() const;

    /// tell the parser to validate
    void validate(bool doValidate);

    /// Get Validation ID and IDREF
    IDValidate idSet();

    /// Setup Validation ID and IDREF
    void  createIdSet();

    /// push a new context, for parse, maybe with EntityData
    void pushContext(string data, bool inScope, EntityData edata);

    /// pop current parsing context
    void popContext();

    /// process the context as entity data, mark encounted entities in stk,
    bool expandEntityData(out string result, StringSet stk, out int refType);

    /// Send an invalid errorstack messages to DOMErrorHandler
    void reportInvalid();

    /// return default normalised version of attribute value, maybe in current context
    string attributeNormalize(string value);

    /// recursive attribute normalisation, for entity replacement
    void attributeTextReplace(string src, ref string value, uint callct);

    /// Return current input context as string with replaced character references
    bool textReplaceCharRef(out string opt);

    /// From entity source, and flag internal/external entity , replace all general entities. Mark those encountered in StringSet stk.
    bool textReplaceEntities(bool isInternal, string src, ref string opt, ref StringSet stk);

    /// Current parse state in a Parameter Entity (DTD)
    bool inParamEntity() const;

    /// Current parse state is in a General Entity (&xml;)
    bool inGeneralEntity()  const;

    /// Currently parsing a DTD
    bool inDTD();

    /// Name of entity being parsed, if any
    string getEntityName();

    /// text is a proper tag name
    bool isXmlName(const(char)[] dval);

    /// text uses proper Xml name characters
    bool isNmToken(const(char)[] dval);

    /// System paths, list of paths for looking up external entities
    void systemPaths(string[] paths);
    string[] systemPaths();

    /// given the system URI, find the full path to object, using systemPaths
    bool getSystemPath(string sysid, out string uri);

    /// throw not well formed xml
    void throwNotWellFormed(string msg);

    /// throw parse error
    void throwParseError(string msg);

    /// parse encountered unknown entity
    void throwUnknownEntity(string entity);

    /// set delegate for exception handling prior to throw
    void setPrepareThrowDg(PrepareThrowDg dg);

	/// allow delagate to be borrowed
    PrepareThrowDg getPrepareThrowDg();

    /// set delegate for getting invalid messages
    void setReportInvalidDg(ReportInvalidDg dg);

    /// get delegate for getting invalid messages
    ReportInvalidDg getReportInvalidDg();

    /// generic thing to set.
    void setParameter(string name, Variant n);

	void setProcessingInstructionDg(ProcessingInstructionDg dg);

    /// declared xml version
    double xmlVersion();


    /// return indication of where parser got to.
    void getLocation(ref SourceRef sref);


    /// throw indexed error message
    void throwErrorCode(ParseErrorCode);

    /// Allow setup or addition to a character entity map
    void setEntityValue(string entityName, string value);

};



/// ensure Context state pops when leaving scope
struct contextPopper
{
    private IXMLParser fp_;


    /// Make a new context
    this(IXMLParser fp, string data)
    {
        fp_ = fp;
        fp_.pushContext(data,true,null);
    }
    /// Ensure existing context is popped on scope exit
    this(IXMLParser fp)
    {
        fp_ = fp;
    }

    /// pop on scope exit
    ~this()
    {
        fp_.popContext();
    }
}



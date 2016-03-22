module std.xml2.sax;

/++
 + Authors:
 + Alexander J. Vincent, ajvincent@gmail.com
 +
 + Date:
 + March 21, 2016
 +
 + Standards:
 + Derived from http://sax.sourceforge.net/ revision sax2r3
 + https://sourceforge.net/projects/sax/files/sax/SAX%202.0.2%20%28sax2r3%29%20final/sax2r3.zip/download
 + and from Mozilla's SAXParser implementation at
 + http://mxr.mozilla.org/mozilla-release/source/parser/xml/
 +
 + Note:
 + This code makes no attempts to deal with character encodings.  The input is
 + assumed to be a string in parse(), and all interface callbacks receive string
 + arguments where appropriate.
 +/

import std.string;
import std.exception;

// Base classes.

/++
 + Mapping of document events to source markup's line number and column number.
 +/
class Locator
{
    public:
        /++
         + The column number where the current document event ends.
         +/
        uint columnNumber;

        /++
         + The line number where the current document event ends.
         +/
        uint lineNumber;

        /++
         + The public identifier for the current document event.
         +/
        string systemId;

        /++
         + The system identifier for the current document event.
         +/
        string publicId;

        /* XXX ajvincent Should we have a string for filename or URI?
           It's not part of the specification, nor similar API's, but it could
           be convenient to have, particularly if we ever have a
           SAXParser.parseFromURI method...
           
           On the other hand, less is faster.
        */

        this(uint line, uint col, string sysId = null, string pubId = null)
        {
            lineNumber = line;
            columnNumber = col;
            systemId = sysId;
            publicId = pubId;
        };
};

unittest
{
    auto x = new Locator(12, 15, "foo");
    assert(x.lineNumber == 12);
    assert(x.columnNumber == 15);
    assert(x.systemId == "foo");
    assert(x.publicId == null);
}

class Attribute
{
    public:
        /++
         + The attribute's XML qualified (prefixed) name.
         +/
        immutable string qName;

        /++
         + The attribute's namespace URI.
         +/
        immutable string uri;

        /++
         + The attribute's value.
         +/
        immutable string value;

        /++
         + The attribute's local name.
         +/
        @property string localName()
        {
            auto colon = qName.indexOf(":");
            return (colon == -1) ? qName : qName[(colon + 1) .. $];
        };

        /++
         + The attribute's prefix.
         +/
        @property string prefix()
        {
            auto colon = qName.indexOf(":");
            return (colon == -1) ? null : qName[0 .. colon];
        };

        /++
         + Params:
         +  nsURI         = the Namespace URI, or the empty string if the
         +                  element has no Namespace URI or if Namespace
         +                  processing is not being performed.
         +  qualifiedName = the qualified name (with prefix), or the empty
         +                  string if qualified names are not available.
         +  attrValue     = the value of the attribute to set.
         +/
        this(string namespaceURI, string qualifiedName, string attrValue)
        {
            uri = namespaceURI;
            qName = qualifiedName;
            value = attrValue;
        };
};

unittest
{
    auto x = new Attribute(
        "http://www.w3.org/2000/xmlns/",
        "xmlns:xlink",
        "http://www.w3.org/1999/xlink"
    );
    assert(x.uri == "http://www.w3.org/2000/xmlns/");
    assert(x.qName == "xmlns:xlink");
    assert(x.prefix == "xmlns");
    assert(x.localName == "xlink");
    assert(x.value == "http://www.w3.org/1999/xlink");

    x = new Attribute(
        null,
        "id",
        "foo"
    );
    assert(x.uri == null);
    assert(x.qName == "id");
    assert(x.prefix == null);
    assert(x.localName == "id");
    assert(x.value == "foo");

    x = new Attribute(
        "about:blank",
        "foo:bar:baz",
        "foo"
    );
    assert(x.uri == "about:blank");
    assert(x.qName == "foo:bar:baz");
    assert(x.prefix == "foo");
    assert(x.localName == "bar:baz");
    assert(x.value == "foo");
};

/+ XXX ajvincent The SAXException and SAXParseException classes are not stable,
   and should not be treated as such.  In particular, at this time, they have
   not been tested.
 +/

/++
 + Encapsulate a general SAX error or warning.
 +
 + This class can contain basic error or warning information from either the XML
 + parser or the application: a parser writer or application writer can subclass
 + it to provide additional functionality. SAX handlers may throw this exception
 + or any exception subclassed from it.
 +
 + If the application needs to pass through other types of exceptions, it must
 + wrap those exceptions in a SAXException or an exception derived from a
 + SAXException.
 +
 + If the parser or application needs to include information about a specific
 + location in an XML document, it should use the SAXParseException subclass.
 +/
class SAXException : Exception
{
    /+ XXX ajvincent Why reorder the arguments?  Only because SAXException is
       specified this way in the saxproject documentation.  I'm willing to
       discard this entirely.
    +/
    this(
        string message,
        Exception e = null,
        string fileName = __FILE__,
        size_t lineNumber = __LINE__
    )
    {
        super(message, fileName, lineNumber, e);
    }
};

/++
 + Encapsulate an XML parse error or warning.
 +
 + This exception may include information for locating the error in the original
 + XML document, as if it came from a Locator object. Note that although the
 + application will receive a SAXParseException as the argument to the handlers
 + in the ErrorHandler interface, the application is not actually required to
 + throw the exception; instead, it can simply read the information in it and
 + take a different action.
 +
 + Since this exception is a subclass of SAXException, it inherits the ability
 + to wrap another exception.
 +/
class SAXParseException : SAXException
{
    this(
        string message,
        Locator loc,
        Exception e = null,
        string file = __FILE__,
        size_t line=__LINE__
    )
    {
        super(message, e, __FILE__, __LINE__);
        locator = loc;
    }
    

    /++
     + The passed-in Locator.
     +/
    Locator locator;
};

// Handlers.
/+

/+ Disabled for now based on the author's lack of experience
interface DTDHandler
{
    // throws SAXException
    void notationDecl(
        string name,
        string publicId,
        string systemId
    );

    // throws SAXException
    void unparsedEntityDecl(
        string name,
        string publicId,
        string systemId,
        string notationName
    );
};
+/

/+ Disabled for now - the author has no experience in Mozilla with this.

// Required for EntityResolver.
interface InputSource
{
    // not defined yet
};

interface EntityResolver
{
    InputSource resolveEntity(
        string publicId,
        string systemId
    ); // throws SAXException, IOException
};
+/

+/

alias delegateNoArgs  = void delegate();

alias delegateString1 = void delegate(string a);
alias delegateString2 = void delegate(string a, string b);
alias delegateString3 = void delegate(string a, string b, string c);
alias delegateString4 = void delegate(string a, string b, string c, string d);

alias delegateAttribute = void delegate(Attribute attr);

alias delegateSAXException = void delegate(
    string type,
    SAXParseException exception
);

/++
 + Interface for reading an XML document using callbacks.
 +
 + XMLReader is the interface that an XML parser's SAX2 driver must implement.
 + This interface allows an application to set and query features and properties
 + in the parser, to register event handlers for document processing, and to
 + initiate a document parse.
 +
 + All SAX interfaces are assumed to be synchronous: the parse methods must not
 + return until parsing is complete, and readers must wait for an event-handler
 + callback to return before reporting the next event.
 +/
class XMLReader
{
    public:
        /++
         + Receive notification of the beginning of a document.
         +
         + The SAX parser will invoke this method only once, before any other event
         + callbacks (except for setting documentLocator).
         +
         + Throws: SAXException on failure.
         +/
        delegateNoArgs startDocument;

        /++
         + Receive notification of the end of a document.
         +
         + The SAX parser will invoke this method only once, and it will be the last
         + method invoked during the parse. The parser shall not invoke this method
         + until it has either abandoned parsing (because of an unrecoverable error)
         + or reached the end of input.
         +
         + Throws: SAXException on failure.
         +/
         /+ From the official specification:
            + There is an apparent contradiction between the documentation for this
            + method and the documentation for ErrorHandler.fatalError(). Until this
            + ambiguity is resolved in a future major release, clients should make no
            + assumptions about whether endDocument() will or will not be invoked when
            + the parser has reported a fatalError() or thrown an exception.

            The std.xml2 SAXParser will invoke endDocument after a fatalError call.
         +/
        delegateNoArgs endDocument;

        /++
         + Receive notification of the beginning of an element.
         +
         + The SAX Parser will invoke this method at the beginning of every element
         + in the XML document; there will be a corresponding endElement event for
         + every startElement event (even when the element is empty). All of the
         + element's content will be reported, in order, before the corresponding
         + endElement event.
         +
         + This event allows up to three name components for each element:
         +
         +   the Namespace URI;
         +   the local name; and
         +   the qualified (prefixed) name.
         +
         + Any or all of these may be provided, depending on the values of the
         + http://xml.org/sax/features/namespaces and the
         + http://xml.org/sax/features/namespace-prefixes properties:
         + the Namespace URI and local name are required when the namespaces
         +   property is true (the default), and are optional when the namespaces
         +   property is false (if one is specified, both must be);
         + the qualified name is required when the namespace-prefixes property is
         +   true, and is optional when the namespace-prefixes property is false
         +   (the default).
         +
         + Params:
         +  uri =   the Namespace URI, or the empty string if the element has no
         +          Namespace URI or if Namespace processing is not being
         +          performed.
         +  qName = the qualified name (with prefix), or the empty string if
         +          qualified names are not available.
         + Throws: SAXException on failure.
         +/
        delegateString2 startElement;

        /++
         + Note that the attribute list provided will contain only attributes
         + with explicit values (specified or defaulted): #IMPLIED attributes
         + will be omitted. The attribute list will contain attributes used for
         + Namespace declarations (xmlns* attributes) only if the
         + http://xml.org/sax/features/namespace-prefixes property is true (it
         + is false by default, and support for a true value is optional).
         +
         + Like characters(), attribute values may have characters that need
         + more than one char value.
         +
         + Author's note:  This is intended as a convenience method, to give an
         + object with automatic deduction of localName and prefix from the
         + qualified name.
         +
         + See_Also: addAttributeByStrings
         +
         + Params:
         +   attr = The attribute object.
         +/
        delegateAttribute addAttributeObject;

        /++
         + An alternate method for receiving attribute notifications, if you do
         + not want to receive Attribute objects.
         +
         + This will NOT be called if addAttributeObject is set.
         +
         + Params:
         +  uri =   the Namespace URI, or the empty string if the element has no
         +          Namespace URI or if Namespace processing is not being
         +          performed.
         +  qName = the qualified name (with prefix), or the empty string if
         +          qualified names are not available.
         +  value = the attribute's value.
         +/
        delegateString3 addAttributeByStrings;

        /++
         + Receive notification of the end of an element.
         +
         + The SAX Parser will invoke this method at the end of every element in the
         + XML document; there will be a corresponding startElement event for every
         + endElement event (even when the element is empty).
         +
         + For information on the names, see startElement.
         +
         + Params:
         +  uri =       the Namespace URI, or the empty string if the element has no
         +              Namespace URI or if Namespace processing is not being
         +              performed.
         +  qName =     the qualified name (with prefix), or the empty string if
         +              qualified names are not available.
         +
         + Throws: SAXException on failure.
         +/
        delegateString2 endElement;

        /++
         + Receive notification of character data.
         +
         + The Parser will call this method to report each chunk of character data.
         + SAX parsers may return all contiguous character data in a single chunk,
         + or they may split it into several chunks; however, all of the characters
         + in any single event must come from the same external entity so that the
         + Locator provides useful information.
         +
         + Note that some parsers will report whitespace in element content using
         + the ignorableWhitespace method rather than this one (validating parsers
         + must do so).
         +
         + Params:
         +   ch = the characters from the XML document
         +
         + Throws: SAXException on failure.
         +/
        delegateString1 characters;

        /++
         + Receive notification of ignorable whitespace in element content.
         +
         + Validating Parsers must use this method to report each chunk of
         + whitespace in element content (see the W3C XML 1.0 recommendation,
         + section 2.10): non-validating parsers may also use this method if they
         + are capable of parsing and using content models.
         +
         + SAX parsers may return all contiguous whitespace in a single chunk, or
         + they may split it into several chunks; however, all of the characters in
         + any single event must come from the same external entity, so that the
         + Locator provides useful information.
         +
         + Params:
         +   ch = the characters from the XML document.
         +
         + Throws: SAXException on failure.
         +/
        delegateString1 ignorableWhitespace;

        /++
         + Receive notification of a processing instruction.
         +
         + The Parser will invoke this method once for each processing instruction
         + found: note that processing instructions may occur before or after the
         + main document element.
         +
         + A SAX parser must never report an XML declaration (XML 1.0, section 2.8)
         + or a text declaration (XML 1.0, section 4.3.1) using this method.
         +
         + Note: The nonstandard XMLDeclarationHandler interface is for that
         + purpose.
         +
         + Params:
         +   target = the processing instruction target
         +   data =   the processing instruction data, or null if none was supplied.
         +            The data does not include any whitespace separating it from
         +            the target.
         +
         + Throws: SAXException on failure.
         +/
        delegateString2 processingInstruction;

        /++
         + Begin the scope of a prefix-URI Namespace mapping.
         +
         + The information from this event is not necessary for normal Namespace
         + processing: the SAX XML reader will automatically replace prefixes for
         + element and attribute names when the
         + http://xml.org/sax/features/namespaces feature is true (the default).
         +
         + There are cases, however, when applications need to use prefixes in
         + character data or in attribute values, where they cannot safely be
         + expanded automatically; the start/endPrefixMapping event supplies the
         + information to the application to expand prefixes in those contexts
         + itself, if necessary.
         +
         + Note that start/endPrefixMapping events are not guaranteed to be
         + properly nested relative to each other: all startPrefixMapping events
         + will occur immediately before the corresponding startElement event, and
         + all endPrefixMapping events will occur immediately after the
         + corresponding endElement event, but their order is not otherwise
         + guaranteed.
         +
         + There should never be start/endPrefixMapping events for the "xml" prefix,
         + since it is predeclared and immutable.
         +
         + Note: Likewise, the "xmlns" prefix is reserved and will not appear here.
         +
         + Params:
         +   prefix = the Namespace prefix being declared. An empty string is used
         +            for the default element namespace, which has no prefix.
         +   uri =    the Namespace URI the prefix is mapped to.
         +
         + Throws: SAXException on failure.
         +/
        delegateString2 startPrefixMapping;

        /++
         + End the scope of a prefix-URI mapping.  See startPrefixMapping for
         + details.
         +
         + Params:
         +   prefix = the Namespace prefix being declared. An empty string is used
         +            for the default element namespace, which has no prefix.
         +
         + Throws: SAXException on failure.
         +/
        delegateString1 endPrefixMapping;

        /+ Disabled for now based on the author's lack of experience
        // throws SAXException
        delegateString1 skippedEntity;
        +/

        /+ Disabled for now based on discussion with Robert Schadek, xml2
           module owner: updating the content handler's locator before calling
           each method could slow us down drastically.
        Locator documentLocator;
        +/

        /++
         + Report the start of DTD declarations, if any.
         + This method is intended to report the beginning of the DOCTYPE
         + declaration; if the document has no DOCTYPE declaration, this method will
         + not be invoked.
         +
         + All declarations reported through DTDHandler or DeclHandler events must
         + appear between the startDTD and endDTD events. Declarations are assumed
         + to belong to the internal DTD subset unless they appear between
         + startEntity and endEntity events. Comments and processing instructions
         + from the DTD should also be reported between the startDTD and endDTD
         + events, in their original order of (logical) occurrence; they are not
         + required to appear in their correct locations relative to DTDHandler or
         + DeclHandler events, however.
         +
         + Note that the start/endDTD events will appear within the
         + start/endDocument events from ContentHandler and before the first
         + startElement event.
         +
         + Params:
         +   name =     The document type name.
         +   publicId = The declared public identifier for the external DTD subset,
         +              or null if none was declared.
         +   systemId = The declared system identifier for the external DTD subset,
         +              or null if none was declared. (Note that this is not
         +              resolved against the document base URI.)
         +
         + Throws: SAXException on failure.
         +/
        delegateString3 startDTD;

        /++
         + Report the end of DTD declarations.
         +
         + This method is intended to report the end of the DOCTYPE declaration;
         + if the document has no DOCTYPE declaration, this method will not be
         + invoked.
         +
         + Throws: SAXException on failure.
         +/
        delegateNoArgs endDTD;

        /++
         + Report the end of a CDATA section.
         +
         + The contents of the CDATA section will be reported through the
         + regular characters event; this event is intended only to report the
         + boundary.
         +
         + Throws: SAXException on failure.
         +/
        delegateNoArgs endCDATA;

        /++
         + Report the beginning of some internal and external XML entities.
         +
         + The reporting of parameter entities (including the external DTD
         + subset) is optional, and SAX2 drivers that report LexicalHandler
         + events may not implement it; you can use the
         + http://xml.org/sax/features/lexical-handler/parameter-entities
         + feature to query or control the reporting of parameter entities.
         +
         + General entities are reported with their regular names, parameter
         + entities have '%' prepended to their names, and the external DTD
         + subset has the pseudo-entity name "[dtd]".
         +
         + When a SAX2 driver is providing these events, all other events must
         + be properly nested within start/end entity events. There is no
         + additional requirement that events from DeclHandler or DTDHandler be
         + properly ordered.
         +
         + Note that skipped entities will be reported through the skippedEntity
         + event, which is part of the ContentHandler interface.
         +
         + Because of the streaming event model that SAX uses, some entity
         + boundaries cannot be reported under any circumstances:
         + * general entities within attribute values
         + * parameter entities within declarations
         + These will be silently expanded, with no indication of where the
         + original entity boundaries were.
         + Note also that the boundaries of character references (which are not
         + really entities anyway) are not reported.
         +
         + All start/endEntity events must be properly nested.
         +
         + Params:
         +   name = The name of the entity. If it is a parameter entity, the
         +          name will begin with '%', and if it is the external DTD
         +          subset, it will be "[dtd]".
         +
         + Throws: SAXException on failure.
         +/
        delegateString1 startEntity;

        /++
         + Report the end of an entity.
         +
         + Params:
         +   name = The name of the entity that is ending.
         +
         + Throws: SAXException on failure.
         +/
        delegateString1 endEntity;

        /++
         + Report an XML comment anywhere in the document.
         +
         + This callback will be used for comments inside or outside the
         + document element, including comments in the external DTD subset (if
         + read).  Comments in the DTD must be properly nested inside
         + start/endDTD and start/endEntity events (if used).
         +/
        delegateString1 comment;

        /++
         + Report the XML declaration at the beginning of a XML document.
         +
         + Author's note: This is a non-standard method.  I believe it very
         + useful to have, especially the encoding parameter.
         +
         + Params:
         +   xmlVersion: The XML version.  (As of now, only "1.0" or "1.1"
         +               exist.)
         +   encoding:   The character encoding in the declaration.  Replaces
         +               the charset property of the HTTP Content-Type header.
         +   standalone: Reflects the "standalone" property of the XML
         +               declaration.
         +/
        delegateString3 xmlDeclaration;

        /++
         + Receive notification of an error.
         + If a SAX application needs to implement customized error handling, it
         + must implement this delegate.  The parser will then report all errors
         + and warnings through this interface.
         +
         + WARNING: If an application does not register a handleError delegate,
         + XML parsing errors will go unreported, except that SAXParseExceptions
         + will be thrown for fatal errors. In order to detect validity errors,
         + a handleError delegate that does something with type "error" calls
         + must be registered.
         +
         + For XML processing errors, a SAX driver must use this delegate in
         + preference to throwing an exception: it is up to the application to
         + decide whether to throw an exception for different types of errors
         + and warnings. Note, however, that there is no requirement that the
         + parser continue to report additional errors after a call to
         + handleError with type "fatal". In other words, a SAX driver class may
         + throw an exception after reporting any fatal error. Also, parsers may
         + throw appropriate exceptions for non-XML errors. For example,
         + XMLReader.parse() would throw an Exception for errors accessing
         + entities or the document.
         +
         + If the type argument is "fatal":
         +    This corresponds to the definition of "fatal error" in section 1.2
         +    of the W3C XML 1.0 Recommendation.  For example, a parser would
         +    use this callback to report the violation of a well-formedness
         +    constraint.
         +
         +    The application must assume that the document is unusable after
         +    the parser has invoked this method, and should continue (if at
         +    all) only for the sake of collecting additional error messages: in
         +    fact, SAX parsers are free to stop reporting any other events once
         +    this method has been invoked.
            /+ From the official specification:
               + There is an apparent contradiction between the documentation for
               + this method and the documentation for ErrorHandler.fatalError().
               + Until this ambiguity is resolved in a future major release,
               + clients should make no assumptions about whether endDocument()
               + will or will not be invoked when the parser has reported a
               + fatalError() or thrown an exception.

               The std.xml2 SAXParser will invoke endDocument after a fatalError
               call.
            +/
         +
         + If the type argument is "error":
         +    This corresponds to the definition of "error" in section 1.2 of
         +    the W3C XML 1.0 Recommendation. For example, a validating parser
         +    would use this callback to report the violation of a validity
         +    constraint. The default behaviour is to take no action.
         +
         +    The SAX parser must continue to provide normal parsing events
         +    after invoking this method: it should still be possible for the
         +    application to process the document through to the end. If the
         +    application cannot do so, then the parser should report a fatal
         +    error even if the XML recommendation does not require it to do so.
         +
         +    Filters may use this method to report other, non-XML errors as
         +    well.
         +
         + If the type is "warning":
         +    SAX parsers will use this method to report conditions that are not
         +    errors or fatal errors as defined by the XML recommendation. The
         +    default behaviour is to take no action.
         +
         +    The SAX parser must continue to provide normal parsing events
         +    after invoking this method: it should still be possible for the
         +    application to process the document through to the end.
         +
         +    Filters may use this method to report other, non-XML warnings as
         +    well.
         +
         +    Note:  The author does not yet know of a case where we would
         +    invoke this.
         +
         + Params:
         +   type:      The type of exception ("fatal", "error", "warning")
         +   exception: The error information encapsulated in a
         +              SAXParseException.
         + Throws: SAXException (any, possibly wrapping another exception).
         +/
        delegateSAXException handleError;


        /+ Disabled for now - the author has no experience with these.
        DTDHandler dtdHandler;
        EntityResolver entityResolver;
        +/

        /+ Author's note:  features and properties might be replaceable with
           simple bitflags and associative arrays, respectively.  I haven't
           thought about that yet.
        +/
        bool getFeature(string name)
        {
            // not implemented yet
            return false;
        };
        void setFeature(string name, bool value)
        {
            // not implemented yet
        };

        Object getProperty(string name)
        {
            // not implemented yet
            return null;
        };
        void setProperty(string name, Object value)
        {
            // not implemented yet
        };

        void parse(string input)
        {
            // not implemented yet
        };
};

unittest {
    struct EventSequence {
        public:
            string[] results;
            void startDoc() {
                results ~= "startDocument";
            }
            void endDoc() {
                results ~= "endDocument";
            }
    }

    // Tests for setting and calling callbacks.
    {
        auto reader = new XMLReader;
        auto events = new EventSequence;

        reader.startDocument = &events.startDoc;
        reader.endDocument = &events.endDoc;

        reader.startDocument();
        reader.endDocument();

        assert(events.results == [
            "startDocument",
            "endDocument"
        ]);
    }    
}

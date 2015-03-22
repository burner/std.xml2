/**
	A DOM very similar to Java DOM.
	with navigation between linked parent, child and sibling nodes.

Authors: Michael Rynn
Licence: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Distributed under the Boost Software License, Version 1.0.

For larger Documents, with 1000's of element nodes, it is advisable to call the Document method
explode, because the GC may find the inter-linked pointer relationships indigestable. Demolishers,
should be aware the GC will terminate with an exception, if any other references to deleted objects are extant after calling explode.
Element subtrees of Document need to be removed from the Document tree before explode is called, if they are to be kept around.
Only linked Nodes are deleted. String content, is considered untouchable and is left entirely alone for the GC.

*/

module xmlp.xmlp.linkdom;

import std.stdint;
import std.conv;
import std.array;
import alt.zstring;

import std.string;
import core.memory;
import core.stdc.string;
import xmlp.xmlp.charinput;
import xmlp.xmlp.parseitem;
import xmlp.xmlp.coreprint;
import xmlp.xmlp.dtdvalidate;
import xmlp.xmlp.entitydata;

import std.stream;
import std.exception;


static const string xmlNamespaceURI = "http://www.w3.org/XML/1998/namespace";
static const string xmlnsURI = "http://www.w3.org/2000/xmlns/";



version(CustomAA)
{
	// This did not seem to  help garbage collection or performance.
	import alt.arraymap; 
	alias HashTable!(string, AttrNS) AttrNSMap;
}
else {
	alias AttrNS[string] AttrNSMap;
}

version(GC_STATS) {
	import alt.gcstats;
}
/// This modules exception class
class DOMFail : Exception
{
    this(string msg)
    {
        super(msg);
    }
}

void DOMClassException(string msg, string name) //throw(DOMFail*)
{
    throw new DOMFail(text(msg,name));
}


void notImplemented(string msg)
{
    throw new DOMFail(text("Not implemented: ",msg));
}

alias scope int delegate(Node n) NodeVisitFn;
alias int function(Node n1, Node n2) NodeCompareFn;

/// return a node as a string value
string NodeAsString(Node n)
{
    return (n.getNodeType()==NodeType.Element_node) ? n.getTextContent() : n.getNodeValue();
}

/// Wraps naked Node[] as class.
class NodeList
{
    Node[]			items_;
public:
    @property final uintptr_t getLength()
    {
        return items_.length;
    }

    final Node item(uintptr_t ix)
    {
        return items_[ix];
    }

    /// constructor
    this()
    {
    }
    /// constructor
    this(Node[] nlist)
    {
        items_ = nlist;
    }
    /// constructor
    this(Node link)
    {
        addLinkList(link);
    }
    /// append all next sibling nodes
    void addLinkList(Node link)
    {
        auto app = appender(items_);

        while(link !is null)
        {
            app.put(link);
            link = link.getNextSibling();
        }
        items_ = app.data();
    }

    /// apply delegate to each member
    int opApply(scope int delegate(ref Node) dg)
    {
        for(size_t ix = 0; ix < items_.length; ix++)
        {
            int result = dg(items_[ix]);
            if (result)
                return result;
        }
        return 0;
    }

    /// support array append
    void opCatAssign(Node[] nlist)
    {
        items_ ~= nlist;
    }

    /// support single append
    void opCatAssign(Node n)
    {
        items_ ~= n;
    }

    /// set length to 0
    void clear()
    {
        items_.length = 0;
    }

    /// Assign as one node length.
    void assignOne(Node n)
    {
        items_.length = 1;
        items_[0] = n;
    }

    /// index support
    Node opIndex(size_t ix)
    {
        return items_[ix];
    }

    /// raw access
    Node[] items()
    {
        return items_;
    }

    /// length property
    @property const size_t length()
    {
        return items_.length;
    }

    /// assign raw array
    void setItems(Node[] all)
    {
        items_ = all;
    }

}

/// Java dom class name for a string[] wrapper
class StringList
{
protected:
    string[] items_;
public:

    this()
    {
    }


    /// Its quite simple
    string[] items()
    {
        return items_;
    }
    /// Its quite simple
    this( string[] list)
    {
        items_ = list;
    }
    /// Simple search
    bool contains(string s)
    {
        for(uint i = 0; i < items_.length; i++)
            if (cmp(s,items_[i]) == 0)
                return true;
        return false;
    }
    /// property
    @property final uintptr_t getLength()
    {
        return items_.length;
    }

    /// checked access
    string item(uintptr_t ix)
    {
        if	(ix >= items_.length)
            return null;
        return items_[ix];
    }

};


/// Used to communicate the source position of an error
class DOMLocator :  Object
{
package:
    // TODO : get character units size
    intptr_t		charsOffset; // position in stream Characters
    intptr_t		lineNumber;
    intptr_t		colNumber;
public:
    this()
    {
        charsOffset = -1;
        lineNumber = -1;
        colNumber = -1;
    }

    /// Not sure if supposed to depend on stream character size.
    intptr_t getByteOffset()
    {
        return charsOffset;
    }
    /// characters in the line
    intptr_t getColumnNumber()
    {
        return colNumber;
    }
    /// The line number
    intptr_t getLineNumber()
    {
        return lineNumber;
    }
    /// not implemented
    Node getRelatedNode()
    {
        return null;
    }
    /// not implemented


    intptr_t getUtf16Offset()
    {
        return -1;
    }
}
/// Used to communicate error details
class DOMError  :  Object
{
protected:
    DOMLocator		location_;
    string			message_;
    uint			severity_;
    Exception		theError_;
public:

    enum
    {
        NO_ERROR = 0,
        SEVERITY_WARNING,
        SEVERITY_ERROR,
        SEVERITY_FATAL_ERROR
    }
    /// constructor
    this(string msg)
    {
        message_ = msg;
    }

    package void setSeverity(uint level)
    {
        severity_ = level;
    }

    package void setException(Exception x)
    {
        theError_ = x;
    }

    package void setLocator(DOMLocator loc)
    {
        location_ = loc;
    }
    /// DOM property
    DOMLocator getLocation()
    {
        return location_;
    }
    /// DOM property
    string getMessage()
    {
        return message_;
    }
    /// DOM property
    uint   getSeverity()
    {
        return severity_;
    }
    /// DOM property
    Object getRelatedData()
    {
        return null;
    }
    /// DOM property
    Object getRelatedException()
    {
        return theError_;
    }
    /// DOM property
    string getType()
    {
        return "null";
    }
}
/**
	By setting this using the DOMConfiguration interface,
	can get to handle, report and even veto some errors
*/

class DOMErrorHandler
{
    /// Return true if error is non-fatal and it was handled.
    bool handleError(DOMError error)
    {
        return false; // stop processing
    }
}

/// A little factory class
class DOMImplementation
{
    /// Make DocumentType node
    DocumentType createDocumentType(string qualName, string publicId, string systemId)
    {
        DocumentType dtype = new DocumentType(qualName);
        dtype.publicId = publicId;
        dtype.systemId = systemId;
        return dtype;

    }
    /// Make a Document
    Document createDocument(string namespaceURI, string qualName, DocumentType docType)
    {
        string name = (namespaceURI !is null)? namespaceURI ~ ":" ~ qualName : qualName;
        DocumentType dtype = (docType is null) ? null : cast(DocumentType) docType;

        Document doc = new Document(dtype,name);
        doc.setImplementation(this);

        return doc;
    }

    /// Not implemented
    bool hasFeature(string feature, string versionStr)
    {
        notImplemented("hasFeature");
        return false;
    }
}

import std.variant;

/// Only works for setting the DOMErrorHandler at present
class DOMConfiguration
{

    Document ownerDoc_;
    Variant[string]	map_;

    /*
    The parameter can be set, if exists in the map_, and
    the value type is the same as the Variant type stored in the map?
    */
public:
    this(Document doc)
    {
        ownerDoc_ = doc;
    }
    /// DOM interface using std.variant
    Variant getParameter(string name)
    {
        return map_[name];
    }

    void setDefaults()
    {
        setParameter("namespaces",Variant(true));
        setParameter("namespace-declarations",Variant(true));

        setParameter("canonical-form",Variant(false));
        setParameter("cdata-sections",Variant(true));
        setParameter("check-character-normalization",Variant(false));
        setParameter("comments",Variant(true));
        setParameter("entities",Variant(true));
        Variant eh = new DOMErrorHandler();
        setParameter("error-handler",eh);
        setParameter("edition",Variant(cast(uint)5));

    }
    /// DOM interface using std.variant
    bool canSetParameter(string name, Variant value)
    {
        // a real implementation would be complex, and check the value
        return (name in map_) !is null;
    }
    /// get names of accessible parameters
    StringList getParameterNames()
    {
        return new StringList(map_.keys());
    }
    /// DOM interface using std.variant
    void setParameter(string name, Variant value)
    {
        map_[name] = value;
        ownerDoc_.configChanged(name);
    }

};

/// DOM accessible parts of DTD, just entities and notations.
class DocumentType : ChildNode
{
package:
    string	publicId;
    string	systemId;

    NamedNodeMap entities_;
    NamedNodeMap notations_;
    string internal_;
	DTDValidate	 dtd_;

public:

    override const NodeType getNodeType()
    {
        return NodeType.Document_type_node;
    }

    string getPublicId()
    {
        return publicId;
    }
    string getSystemId()
    {
        return systemId;
    }
    /// The name isn't used much, but maybe could use for hash identity.
    this(string name)
    {
        id_ = name;
        entities_ = new NamedNodeMap();
        notations_ = new NamedNodeMap();
    }
    /// what good is this?
    string getName()
    {
        return id_;
    }

    /// what good is this?
    string getInternalSubset()
    {
        return internal_;
    }

    override string getNodeName()
    {
        return id_;
    }

    /// Node map for notations
    NamedNodeMap getNotations()
    {
        return notations_;
    }
    /// Node map for entities
    NamedNodeMap getEntities()
    {
        return entities_;
    }
	/// Non DOM method
	DTDValidate getDTD()
	{
		return dtd_;
	}

	void setDTD(DTDValidate dtd)
	{
		dtd_ = dtd;
		if (dtd_.notationMap.length > 0)
		{
			foreach(en ; dtd_.notationMap)
			{
				auto n = new Notation(en);
				notations_.setNamedItem(n);
			}
		}
		if (dtd_.generalEntityMap.length > 0)
		{
			foreach(en ; dtd_.generalEntityMap)
			{
				auto n = new Entity(en);
				entities_.setNamedItem(n);
			}
		}
	}
}

/// Not yet used
class EntityReference : ChildNode
{
public:
    this(string id)
    {
        super(id);
    }
    override string getNodeName()
    {
        return id_;
    }
    override const NodeType getNodeType()
    {
        return NodeType.Entity_Reference_node;
    }
}

/// Parsed and in DOM but not used.
class ProcessingInstruction : ChildNode
{
    string   data_;
public:
    this(string target, string data)
    {
        super(target);
        data_ = data;
    }
    this()
    {
    }
    override string getNodeValue()
    {
        return id_;
    }
    override const NodeType getNodeType()
    {
        return NodeType.Processing_Instruction_node;
    }
    string getTarget()
    {
        return id_;
    }
    override string getNodeName()
    {
        return id_;
    }

    string getData()
    {
        return data_;
    }

    void setData(string data)
    {
        data_ = data;
    }

    override const string toString()
    {
        return makeXmlProcessingInstruction(id_,data_);
    }

}

/// Essential DOM component
class Document : Node
{
    DocumentType	dtd_;
    Element			docElement_;
    Element			rootElement_; // for comments, processing instructions.

    DOMConfiguration		config_;
    DOMImplementation		implementation_;
    DOMErrorHandler			errorHandler_;

    string		version_;
    double			versionNum_;
    uint			edition_ = 5;
    string		encoding_;
    string		inputEncoding_;
    bool			standalone_;
    bool			check_;
    bool			namespaceAware_;
    string		uri_;

public:

    this()
    {
        init("NoName");
    }
	/// Initialise with a name, but this does not make a Document Element.
    this(string name)
    {
        init(name);
    }

	/// Initialise with a Document Element
    this(Element root)
    {
        init("NoName");
        appendChild(root);
    }
    /// Supplied DTD
    this(DocumentType docType,string name)
    {
        init(name);
        dtd_ = docType;
    }

	/// Part of DOM
    override const NodeType getNodeType()
    {
        return NodeType.Document_node;
    }

    /// Document property
    void setInputEncoding(const string value)
    {
        inputEncoding_ = value;
    }
    /// Document property
    void setEncoding(const string value)
    {
        encoding_ = value;
    }
    /// Document property
    bool getStrictErrorChecking()
    {
        return check_;
    }
    void setStrictErrorChecking(bool val)
    {
        check_ = val;
    }

    /// Document property, not available yet
    DocumentType getDoctype()
    {
        return dtd_;
    }

    /// Document property, not available yet
    string getDocumentURI()
    {
        return uri_;
    }

    /// DOM document data root Element
    Element getDocumentElement()
    {
        return docElement_;
    }

    /// Used to get and set parameters in the document.
    DOMConfiguration getDomConfig()
    {
        return config_;
    }

    /// Not used yet
    DOMImplementation getImplementation()
    {
        return implementation_;
    }

    /// Document property
    string getXmlEncoding()
    {
        return encoding_;
    }

    /// Document property
    string getInputEncoding()
    {
        return inputEncoding_;
    }

    /// DOM property: dependency on external documents
    void setXmlStandalone(bool standalone)
    {
        standalone_ = standalone;
    }

    /// DOM property: dependency on external documents
    bool getXmlStandalone()
    {
        return standalone_;
    }

    /// Document property
    void setXmlVersion(string xmlVersion)
    {
        version_ = xmlVersion;
    }

    string getXmlVersion()
    {
        return version_;
    }

    /// Not implemented yet
    Element getElementById(string id)
    {
        return null;
    }

    void configChanged(string param)
    {
        Variant v = config_.getParameter(param);

        if (param ==  "error-handler")
        {
            DOMErrorHandler* p = v.peek!(DOMErrorHandler); // whohoo
            errorHandler_ = (p is null) ? null : *p;
        }
        else if (param == "namespaces")
        {
            namespaceAware_ = v.get!(bool);
        }
        else if (param == "edition")
        {
            edition_ = v.get!(uint);
        }
    }

    Node  adoptNode(Node source)
    {
        NodeType ntype = source.getNodeType();
        switch(ntype)
        {
        case  NodeType.Element_node:

            Element xe = cast(Element)(source);
            xe.setDocument(this);
            xe.setParentNode(docElement_);
            this.setOwner(docElement_);
            return source;
        default:
            break;
        }
        DOMClassException("unsupported node type adoptNode: ",typeid(source).name);
        return null;
    }
    /// support ~=
    void opCatAssign(Element e)
    {
        appendChild(e);
    }

    /// Child must be the only Element or DocType node, comment or processing instruction.
    override Node appendChild(Node newChild)
    {
        NodeType ntype = newChild.getNodeType();
        switch(ntype)
        {
        case  NodeType.Element_node:
        {
            Element xe = cast(Element)(newChild);
            if (docElement_ is null)
            {
                xe.setDocument(this);
                docElement_ = xe;
                rootElement_.appendChild(docElement_);

                return newChild;
            }
            else
                docElement_.appendChild(xe);

            //throw new DOMFail("Already have document element");
        }
        break;
        case  NodeType.Comment_node:
        {
            Comment cmt = cast(Comment)(newChild);
            rootElement_.appendChild(cmt);
            return newChild;
        }
        case  NodeType.Processing_Instruction_node:
        {
            ProcessingInstruction xpi =  cast(ProcessingInstruction)(newChild);
            if (xpi !is null)
            {
                rootElement_.appendChild(xpi);
                return newChild;
            }
        }
        break;
        case NodeType.Document_type_node:
        {
            DocumentType dt = cast(DocumentType)(newChild);
            if (dt !is null)
            {
                if (dtd_ !is null)
                    throw new DOMFail("Already have DocumentType node");

                dtd_ = dt;
                rootElement_.appendChild(dt);
                return newChild;
            }
        }
        break;

        default:
            DOMClassException("Document.appendChild: type not supported ",typeid(newChild).name);
            break;
        }
        return null;
    }

    /// Not useful or tested yet
    Node importNode(Node n, bool deep)
    {
        NodeType ntype = n.getNodeType();
        if (ntype == NodeType.Element_node)
        {
            Element en = cast(Element)(n);
            ElementNS ens = cast(ElementNS)(en);
            if (ens !is null)
            {
                ElementNS ecopyNS = cast(ElementNS)(createElementNS(ens.getNamespaceURI(), ens.getNodeName()));
                importAttributesNS(ens, ecopyNS);
                adoptNode(ecopyNS);
                return ecopyNS;
            }

        }
        DOMClassException("importNode: unsupported type ",typeid(n).name);
        return null;
    }

    /**
    	Not tested or useful yet.
    	Rename one of the documents nodes.
    	The facility to rename a node, is not in the actual Node interface?
    	The local name can be a prefix:name.
    */
    Node renameNode(Node n, string uri, string local)
    {
        NodeType ntype = n.getNodeType();
        switch(ntype)
        {
        case NodeType.Element_node:
        {
            ElementNS en =  cast(ElementNS)( n );
            if (en is null || en.getOwnerDocument() != this)
            {
                throw new DOMFail("renameNode: Not owned by this document");
            }
            en.setIdentity(uri, local);
            return en;
        }

        case NodeType.Attribute_node:
        default:
            break;
        }

        DOMClassException("renameNode: Not supported for ",typeid(n).name);
        return n;
    }

    /// Change owner of the node and its element children to be this document
    int setOwner(Node n)
    {
        // set every child of n to have this as owner?
        Element en = cast(Element)(n);

        int setNodeOwner(Node n)
        {
            Element c = cast(Element) n;
            if (c !is null)
                c.setDocument(this);

            return 1;
        }

        if (en !is null && en.hasChildNodes())
        {
            en.forEachChild(&setNodeOwner);
        }
        return 0;
    }


    /// not implemented properly yet
    void  importAttributesNS(Element src, Element dest)
    {
        int copyAttr(Node n)
        {
            Attr atr = cast(Attr) n;
            if(atr !is null)
                dest.setAttribute(atr.getName(), atr.getValue());
            return 1;
        }

        src.forEachAttr(&copyAttr);
    }

    void init(string name)
    {
        id_ = name;

        standalone_ = true;
        check_ = false; //?
        versionNum_ = 1.0;
        version_ = "1.0";
        encoding_ = "UTF-8";
        inputEncoding_ = encoding_;//?
        config_ = new DOMConfiguration(this);
        config_.setDefaults();
        docElement_ = null;
        rootElement_ = new Element("_root");
        rootElement_.setDocument(this);
        implementation_= null;
        errorHandler_ = null;
        namespaceAware_ = true;
    }



    const void printOut(StringPutDg dg, uint indent = 2)
    {
        printDocument(cast(Document) this, dg, indent);
    }

    const string[] pretty(uint indent)
    {
        Array!string app;
        ImmuteAlloc!char ialloc;

        void addstr(const(char)[] s)
        {
            app.put(ialloc.alloc(s));
        }

        printDocument(cast(Document) this, &addstr, indent);

        return app.toArray;
    }

    void setImplementation(DOMImplementation idom)
    {
        implementation_ = idom;
    }

	void unlink()
	{
		dtd_ = null;
		docElement_= null;
		rootElement_= null; // for comments, processing instructions.
		config_= null;
		implementation_= null;
		errorHandler_= null;
	}


	/// tear everything apart for attempts at garbage collection
	override void explode(bool del)
	{
		auto elem = getRootElement();
		rootElement_ = null;
		elem.explode(del);
		unlink();
		super.explode(del);
	}
		

    package Element getRootElement()
    {
        return rootElement_;
    }

    /// DOM node constructor for this document
    Attr
    createAttribute(string name)
    {
        if (namespaceAware_)
            return new AttrNS(name);
        else
            return new Attr(name);
    }

    /// DOM node constructor for this document
    Attr
    createAttributeNS(string uri, string qname)
    {
        AttrNS result = new AttrNS(uri,qname);
        return result;
    }

    /// DOM node constructor for this document
    CDATASection
    createCDATASection(string data)
    {
        CDATASection result = new CDATASection(data);
        //result.setDocument(this);
        return result;
    }

    /// DOM node constructor for this document
    Comment
    createComment(string data)
    {
        Comment result = new Comment(data);
        //result.setDocument(this);
        return result;
    }
    /// DOM node constructor for this document
    Element
    createElement(string tagName)
    {
        if (namespaceAware_)
            return new ElementNS(tagName);
        else
            return new Element(tagName);

    }
    /// DOM node constructor for this document
    Element
    createElementNS(string uri, string local)
    {
        ElementNS result = new ElementNS(uri, local);
        //result.setDocument(this);
        return result;
    }
    /// DOM node constructor for this document
    EntityReference
    createEntityReference(string name)
    {
        EntityReference result = new EntityReference(name);
        //result.setDocument(this);
        return result;

    }
    /// DOM node constructor for this document
    Text
    createTextNode(string data)
    {
        Text result = new Text(data);
        //result.setDocument(this);
        return result;
    }
    /// DOM node constructor for this document
    ProcessingInstruction
    createProcessingInstruction(string target, string data)
    {
        ProcessingInstruction result = new ProcessingInstruction(target, data);
        //result.setDocument(this);
        return result;
    }

    /// List  nodes without breaking up relationships.
    NodeList
    getElementsByTagName(string name)
    {
        if (docElement_ !is null)
            return docElement_.getElementsByTagName(name);
        else
            return new  NodeList();
    }
    /// List  nodes without breaking up relationships.
    NodeList
    getElementsByTagNameNS(string uri, string local)
    {
        if (docElement_ is null)
            return docElement_.getElementsByTagNameNS(uri,local);
        else
            return new NodeList();
    }

}

/** Not really used yet. Not sure what its good for.
	Holds a linked list of nodes.
*/
class DocumentFragment : Node
{
protected:
    ChildList children_;
public:
    /// empty by nulling
    void clear()
    {
        children_.firstChild_ = null;
        children_.lastChild_ = null;
    }

    /// set the list from first to last
    void set(ChildNode first, ChildNode last)
    {
        children_.firstChild_ = first;
        children_.lastChild_ = last;
    }

    /// DOM method
    override Node getFirstChild()
    {
        return children_.firstChild_;
    }

    /// DOM method
    override Node getLastChild()
    {
        return children_.lastChild_;
    }
    /// DOM method
    override NodeList getChildNodes()
    {
        Node[] items;
        Node   n = children_.firstChild_;
        while (n !is null)
        {
            items ~= n;
            n = n.getNextSibling();
        }
        return new NodeList(items);
    }
    /// Throws exception if child is attached elsewhere
    override Node  appendChild(Node newChild)
    {
        ChildNode xnew = cast(ChildNode) newChild;
        if (xnew is null)
            throw new DOMFail("null child to appendChild");

        children_.linkAppend(xnew);
        xnew.parent_ = this;
        // ownerDoc of elements?
        return newChild;
    }
}

/// Base class of all DOM Nodes, following much of DOM interface.
/// This class has one string field to hold whatever the child wants.
/// This class is abstract. Most methods do nothing.
abstract class Node
{
	version(GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}
    package
    {
        string  id_;
    }
public:
    /// construct
	version(GC_STATS)
	{
		~this()
		{
			gcStatsSum.dec();
		}
	}
	this()
	{
		version(GC_STATS)
			gcStatsSum.inc();
	}

    /// construct
    this(string id)
    {
        id_ = id;
		version(GC_STATS)
			gcStatsSum.inc();
    }
    /// hashable on id_
    override const hash_t toHash()
    {
        return typeid(id_).getHash(&id_);
    }

    /// DOM method returns null, to support non named descendents
    string getNodeName()
    {
        return null;
    }
    /// DOM method returns id_ to support text node descendents;
    string getNodeValue()
    {
        return id_;
    }

    /// DOM method
    void setNodeValue(string val)
    {
        id_ = val;
    }
    /// DOM method
    abstract const NodeType getNodeType();
    /// DOM method
    NodeList getChildNodes()
    {
        notImplemented("cloneNode");
        return null;
    }
    /// DOM method returns null,
    Node getFirstChild()
    {
        return null;
    }
    /// DOM method returns null,
    Node getLastChild()
    {
        return null;
    }
    /// DOM method returns null,
    Node getPreviousSibling()
    {
        return null;
    }
    /// DOM method returns null,
    Node getNextSibling()
    {
        return null;
    }
    /// DOM method returns null,
    NamedNodeMap getAttributes()
    {
        return null;
    }
    /// DOM method returns null,
    Document getOwnerDocument()
    {
        return null;
    }
    /// DOM method returns null,
    Node insertBefore(Node newChild, Node refChild)
    {
        notImplemented("insertBefore");
        return null;
    }
    /// DOM method returns null,
    Node replaceChild(Node newChild, Node oldChild)
    {
        notImplemented("replaceChild");
        return null;
    }
    /// DOM method returns null,
    Node removeChild(Node oldChild)
    {
        notImplemented("removeChild");
        return null;
    }

    /// DOM method returns null,
    Node appendChild(Node newChild)
    {
        notImplemented("appendChild");
        return null;
    }

    /// DOM method returns false,
    bool hasChildNodes()
    {
        return false;
    }

    /// DOM method returns null,
    Node cloneNode(bool deep)
    {
        notImplemented("cloneNode");
        return null;
    }

	/**
		Pre-emptive strike to devastate object, and possibly delete at same tile.
		Destructor, must call with del false, and ideally explode can tell,
		if its job is already done.
	*/
	void explode(bool del)
	{
		if (del)
			delete this;
	}

    /// Not supported
    void normalize() {}

    /// Not supported, yet, returns false
    bool isSupported(string feature, string versionStr)
    {
        return false;
    }

    /// DOM method returns null,
    string getNamespaceURI()
    {
        return null;
    }

    /// DOM method returns null,
    string getPrefix()
    {
        return null;
    }

    /// DOM method
    void setPrefix(string prefix)
    {
        notImplemented("prefix");
    }

    /// DOM method returns null,
    string getLocalName()
    {
        return null;
    }

    /// DOM method returns false,
    bool hasAttributes()
    {
        return false;
    }

    /// DOM method returns null,
    string baseURI()
    {
        return null;
    }

    //uint compareDocumentPosition(Node other){ return DocumentPositionFlag.DISCONNECTED; }

    /// DOM method returns null,
    string getTextContent()
    {
        return null;
    }

    /// not implemented here
    void setTextContent(string textContent)
    {
        notImplemented("textContent");
    }

    bool isSameNode(Node other)
    {
        return false;
    }

    /// not implemented here
    string lookupPrefix(string namespaceURI)
    {
        notImplemented("lookupPrefix");
        return null;
    }

    /// not implemented here
    bool isDefaultNamespace(string namespaceURI)
    {
        notImplemented("isDefaultNamespace");
        return false;
    }

    /// not implemented here
    string lookupNamespaceURI(string prefix)
    {
        notImplemented("lookupNamespaceURI");
        return null;
    }

    /// not implemented here
    bool isEqualNode(Node arg)
    {
        return false;
    }

    /// not implemented here
    Object setUserData(string key, Object data)
    {
        notImplemented("setUserData");
        return null;
    }

    /**
     * Retrieves the object associated with key, last set using setUserData.
     * Params:
     * key = The key the object is associated to.
     * Returns: the object associated to the given
     *   key on this node, null
     *
     */
    /// not implemented, returns null
    Object getUserData(string key)
    {
        return null;
    }

    /// not implemented here
    void setParentNode(Node n)
    {
        notImplemented("setParentNode");
    }

    /// returns null
    Node getParentNode()
    {
        return null;
    }

}

/// For shuffling smallish numbers of nodes.s
static void NodeShellSort(Node[] nodes, NodeCompareFn cmp)
{

    auto limit = nodes.length;
    if (limit < 2)
        return;
    static immutable int gapseq[] =
	[1391376, 463792, 198768, 86961, 33936, 13776, 4592,
	1968, 861, 336, 112, 48, 21, 7, 3, 1];

    for(uint gapix = 0; gapix < gapseq.length; gapix++)
    {
        const int gap = gapseq[gapix];

        for (int i = gap; i < limit; i++)
        {
            Node v = nodes[i];
            int j = i;
            while (j >= gap)
            {
                Node c = nodes[j-gap];
                if (cmp(c,v) > 0)
                {
                    nodes[j] = c;
                    j = j-gap;
                }
                else
                    break;
            }
            nodes[j] = v;
        }
    }
}

/**
	Java DOM class semblance, that stores attributes for an Element,
	Implementation uses a simple list in triggered sort order.
*/
class NamedNodeMap
{
private:
    NodeCompareFn	cmp_;
    Node[]			items_;
    bool			sorted_;
public:

    static int CompareNodes(Node n1, Node n0)
    {
        return cmp(n1.getNodeName(), n0.getNodeName());
    }


    this()
    {
        cmp_ = &CompareNodes;
    }

    /// method
    alias length getLength;

    /// property
    @property  final size_t length()
    {
        return items_.length;
    }

    /// method
    final Node getNamedItem(string name)
    {
        auto ix = findNameIndex(name);
        if (ix >= 0)
            return items_[ix];
        else
            return null;
    }

    /// method
    final Node getNamedItemNS(string nsURI, string local)
    {
        auto ix = findNSLocalIndex(nsURI, local);
        if (ix >= 0)
            return items_[ix];
        else
            return null;
    }

    /// Access may resort the data, if insertion occurred.
    final Node item(uintptr_t ix)
    {
        if (!sorted_)
            sortMe();
        return items_[ix];
    }

    /// Delegate visitor
    final int forEachNode(NodeVisitFn dg)
    {
        if (!sorted_)
            sortMe();
        for(size_t ix = 0; ix < items_.length; ix++)
        {
            int result = dg(items_[ix]);
            if (result)
                return result;
        }
        return 0;
    }
    /// method
    int opApply(scope int delegate(ref Node n) doit)
    {
        if (!sorted_)
            sortMe();
        foreach(n ; items_)
        {
            int result = doit(n);
            if (result != 0)
                return result;
        }
        return 0;
    }
	/**
	Pre-emptive strike to devastate object, and possibly delete at same tile.
	Destructor, must call with del false, and ideally explode can tell,
	if its job is already done.
	*/
	void explode(bool del)
	{
		auto oldItems = items_;
		items_ = [];
	
		foreach(n ; oldItems)
		{
			n.explode(del);
		}
	}

    private void erase(size_t ix)
    {
        auto nlen = items_.length;
        if (ix+1 == nlen)
        {
            items_[ix] = null;
            items_ = (items_.ptr)[0..ix];
            return;
        }
        memmove(cast(void*) &items_[ix], cast(const(void*)) &items_[ix+1], (nlen - ix-1) * Node.sizeof);
        nlen -= 1;
        items_[nlen] = null;
        items_ = (items_.ptr)[0..nlen];
    }

    /// Node removal
    Node removeNamedItem(string name)
    {
        Node result;
        auto ix = findNameIndex(name);
        if (ix >= 0)
        {
            result = items_[ix];
            erase(ix);
        }
        return result;
    }

    /// Node removal, this is untried
    final Node removeNamedItemNS(string nsURI, string local)
    {
        Node result;
        auto ix = findNSLocalIndex(nsURI, local);
        if (ix >= 0)
        {
            result = items_[ix];
            erase(ix);
            sorted_ = false;
        }
        return result;
    }

    /// D style access support
    final Node opIndex(size_t ix)
    {
        if (!sorted_)
            sortMe();
        return items_[ix];
    }

    final Node opIndex(const(char)[] name)
    {
        auto ix = findNameIndex(name);
        if (ix >= 0)
            return items_[ix];
        else
            return null;
    }

    /// return replaced node or null
    final Node setNamedItem(Node n)
    {
        string nodeName = n.getNodeName();
        Node result = null;

        auto ix = findNameIndex(nodeName);
        if (ix >= 0)
        {
            // replace
            result = items_[ix];
            items_[ix] = n;
        }
        else
        {
            // append unsorted
            items_ ~= n;
            sorted_ = false;
        }
        return result;
    }

    /// return replaced node or null
    final Node setNamedItemNS(Node n)
    {
        Node result = null;
        auto ix = findNSLocalIndex(n.getNamespaceURI(), n.getLocalName());
        if (ix >= 0)
        {
            result = items_[ix];
            items_[ix] = n;
        }
        else
        {
            // append unsorted
            items_ ~= n;
        }
        sorted_ = false;
        return result;
    }

	final void clear()
	{
		if (items_ !is null)
			items_.clear();
		items_ = null;
	}
private:

    void sortMe()
    {
        sorted_ = true;
		if (items_.length > 1)
			NodeShellSort(items_, cmp_);
    }
    /// return -1 if not found
    intptr_t findNameIndex(const(char)[] name)
    {
        if (!sorted_)
            sortMe();
        auto bb = cast(size_t)0;
        auto ee = items_.length;
        while (bb < ee)
        {
            auto m = (ee + bb) / 2;
            Node n = items_[m];
            string nodeName = n.getNodeName();
            int cresult = cmp(name,nodeName);
            if (cresult > 0)
                bb = m+1;
            else if (cresult < 0)
                ee = m;
            else
                return cast(int) m;
        }
        return -1;
    }

    intptr_t findNSLocalIndex(string uri, string lname)
    {
        if (uri.length > 0)
        {
            for(size_t i = 0; i < items_.length; i++)
            {
                Node n = items_[i];
                string nURI = n.getNamespaceURI();
                string nLocal = n.getLocalName();
                if ((nURI.ptr) && (nLocal.ptr))
                {
                    int cURI = cmp(nURI,uri);
                    if (cURI == 0)
                    {
                        int cLocal = cmp(nLocal,lname);
                        if (cLocal==0)
                            return i;
                    }
                }
            }
        }
        else
        {
            for(size_t i = 0; i < items_.length; i++)
            {
                Node n = items_[i];
                string nURI = n.getNamespaceURI();
                string nLocal = n.getLocalName();
                if ((nURI.ptr) && (nLocal.ptr))
                {
                    int cLocal = cmp(nLocal,lname);
                    if (cLocal==0)
                        return i;
                }
            }
        }
        return -1;
    }
}

/// abstract class, has a parent and linked sibling nodes
abstract class ChildNode : Node
{
protected:
    Node				parent_;
    ChildNode			next_;
    ChildNode			prev_;
    //Document			ownerDoc_;
public:

    this(string id)
    {
        super(id);
    }
    this()
    {
    }

    /// get all children as array of Node
    static Node[] getNodeList(ChildNode n)
    {
        if (n is null)
            return null;

        Node[] items;
        auto app = appender(items);
        while(n !is null)
        {
            app.put(n);
            n = n.next_;
        }
        return app.data();
    }
    /// ChildNode siblings
    override Node getPreviousSibling()
    {
        return prev_;
    }
    /// ChildNode siblings
    override Node getNextSibling()
    {
        return next_;
    }

    /// set same parent of all linked children
    static void setParent(ChildNode n, Node parent)
    {
        while(n !is null)
        {
            n.parent_ = parent;
            n = n.next_;
        }
    }
    /// set parent
    override void setParentNode(Node p)
    {
        parent_ = p;
    }

    /// get parent
    override Node getParentNode()
    {
        return parent_;
    }

    /** Only Elements actually hold a reference to the ownerDocument.
    	Other nodes can refer via the parent Element.
    */
    override Document getOwnerDocument()
    {
        if (parent_ !is null)
        {
            Element pe = cast(Element) parent_;
            if (pe !is null)
                return pe.getOwnerDocument();
        }
        return null;
    }
    //@property final Node getParentNode() { return lnk.parent_;}
    /*
    void setDocument(Document d)
    {
    	ownerDoc_ = d;
    }

    */
}

/// Linking functions to put in a class.
struct ChildList
{
    ChildNode firstChild_;
    ChildNode lastChild_;

	/// Remove all links at once. Let the GC sort this out!
	void removeAll()
	{
		firstChild_ = null;
		lastChild_ = null;
	}

	bool empty()
	{
		return((firstChild_ is null) && (lastChild_ is null));
	}

    /// remove
    void removeLink(ChildNode ch)
    {
        ChildNode prior = ch.prev_;
        ChildNode post = ch.next_;
        if (prior !is null)
        {
            prior.next_ = ch.next_;
        }
        else
        {
            firstChild_ = ch.next_;
        }
        if (post !is null)
        {
            post.prev_ = ch.prev_;
        }
        else
        {
            lastChild_ = ch.prev_;
        }
		ch.prev_ = null;
		ch.next_ = null;
    }

    /// add
    void  linkAppend(ChildNode cn)
    {
        if (cn.parent_ !is null)
            throw new DOMFail("appended child already has a parent");

        ChildNode prior = lastChild_;
        if (prior is null)
        {
            firstChild_ = cn;
            cn.prev_ = null;
        }
        else
        {
            lastChild_.next_ = cn;
            cn.prev_ = lastChild_;
        }
        cn.next_ = null;
        lastChild_ = cn;
    }

    /// insert a lot
    void chainAppend(ChildNode chainBegin, ChildNode chainEnd)
    {
        ChildNode prior = lastChild_;
        if (prior is null)
        {
            firstChild_ = chainBegin;
            chainBegin.prev_ = null;
        }
        else
        {
            lastChild_.next_ = chainBegin;
            chainBegin.prev_ = lastChild_;

        }
        chainEnd.next_ = null;
        lastChild_ = chainEnd;
    }

    /// only for non-null xref, which must be already a child
    void insertChainBefore(ChildNode chainBegin, ChildNode chainEnd, ChildNode xref)
    {
        assert(xref !is null);
        ChildNode prior = xref.prev_;
        if (prior is null) // insert is before first link
        {
            firstChild_ = chainBegin;
        }
        chainBegin.prev_ = prior;
        xref.prev_ = chainEnd;
        chainEnd.next_ = xref;
    }
    /// only for non-null cref, which must be already a child
    void linkBefore(ChildNode add, ChildNode cref)
    {
        assert(cref !is null);

        ChildNode prior = cref.prev_;
        if (prior is null)
        {
            firstChild_ = add;
        }
        else
        {
            prior.next_ = add;
        }
        add.prev_ = prior;
        add.next_ = cref;
        cref.prev_ = add;
    }
}

/// The Identity is duel, set by uriNS and localName.  The getNodeName returns the prefix:localName.
/// Set local name is assumed to be actually prefix:localName, or just localName.
/// prefix is set by the nearest URI binding up the tree, once inserted in a document.
class ElementNS : Element
{
protected:
    string uriNS_;
    string localName_;

    package void setIdentity(string nsURI, string name)
    {
        id_ = name;
        uriNS_ = nsURI;
        auto pos =  id_.indexOf(':');
        localName_ = (pos >= 0) ? id_[pos+1..$] : id_;
    }

    package void setURI(string nsURI)
    {
        uriNS_ = nsURI;
    }

public:
    /// construct
    this(string  tag)
    {
        setIdentity(null, tag);
    }
    /// construct
    this()
    {
    }
	~this()
	{
		assert(parent_ is null);
	}
    /** Contradicted constructor for Element with same arguments
        If name is localName, then will need to lookup URI local prefix in tree to make id?
    	Find parent node which has xmlns:<prefix> = URI. But at construction do not have parent.
    	So at least a check takes place when adding to document.
    */
    this(string uri, string name)
    {
        setIdentity(uri, name);
    }
    /// return associated URI
    override string getNamespaceURI()
    {
        return uriNS_;
    }

    /// The local name is after a ':', or the full name if no ':'
    override string getLocalName()
    {
        return localName_;
    }

    /// Get local prefix, which might be zero length
    override string getPrefix()
    {
        auto poffset = id_.length - localName_.length;
        return  (poffset > 0) ? id_[0..poffset-1] : "";
    }
    /// DOM attribute management
    override void setAttribute(string name, string value)
    {
        Attr na = new AttrNS(name);
        na.setValue(value);
        setAttributeNode(na);
    }

}


/// wrap an element, and pretend attributes are set[] and get[] by string.
struct ElemAttributeMap
{
    private Element e_;

    this(Element e)
    {
        e_ = e;
    }
    ///  map[string] = support
    void opIndexAssign(string value, string key)
    {
        e_.setAttribute(key,value);
    }

    /// support = map[string]
    string opIndex(string key)
    {
        return e_.getAttribute(key);
    }


};

/// Binds the document tree together.
class Element :  ChildNode
{
	version(GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}
protected:
    NamedNodeMap		attributes_;
    //
    ChildList			children_;
    Document			ownerDoc_;
public:
    /// method
    override Document getOwnerDocument()
    {
        return ownerDoc_;
    }
    /// construct
    this(string  tag)
    {
        super(tag);
		version (GC_STATS)
			gcStatsSum.inc();
    }
    /// construct
    this()
    {
 		version (GC_STATS)
			gcStatsSum.inc();
	}
	/**
		If object is left to garbage collector, explode(false)
		should further dismember in safety, or do nothing.
	*/
	~this()
	{
		explode(false);
 		version (GC_STATS)
			gcStatsSum.dec();
	}
    /// construct, with single child of text content
    this(string tag, string content)
    {
        super(tag);
        auto txt = new Text(content);
        appendChild(txt);
		version (GC_STATS)
			gcStatsSum.inc();
    }
    /// method
    override bool hasAttributes()
    {
        return attributes_ is null ? false : attributes_.getLength > 0;
    }
    /// returns NodeType.Element_node
    override const NodeType getNodeType()
    {
        return NodeType.Element_node;
    }

    /// method
    override bool	 hasChildNodes()
    {
        return children_.firstChild_ !is null;
    }
	
	void countLeaves(ref ulong count)
	{
		count++;
		if (attributes_ !is null)
			count += (attributes_.getLength());

		auto ch = this.getFirstChild();
		while (ch !is null)
		{
			auto elem = cast(Element) ch;
			ch = ch.getNextSibling();
			if (elem !is null)
				elem.countLeaves(count);
			else
				count++;
		}
	}
    /// return children as array
    ChildNode[] childNodes()
    {
        ChildNode[] result;
        ChildNode cn = children_.firstChild_;
        size_t len = 0;
        while(cn !is null)
        {
            cn = cn.next_;
            len += 1;
        }
        if (len > 0)
        {
            result.length = len;
            cn = children_.firstChild_;
            size_t ix = 0;
            while(cn !is null)
            {
                result[ix++] = cn;
                cn = cn.next_;
            }
        }
        return result;
    }
    /// Get attributes interface
    override NamedNodeMap getAttributes()
    {
        return attributes_;
    }

    /// Set and get all the attributes using whatever AttributeMap is
    void setAttributes(AttributeMap amap)
    {
        foreach(k,v ; amap)
        {
            setAttribute(k,v);
        }
    }

    /// DOM method
    @property ElemAttributeMap attributes()
    {
        return ElemAttributeMap(this);
    }
    /*

    */
    /// method
    Attr getAttributeNode(string name)
    {
        if (attributes_ is null)
            return null;
        Node n = attributes_.getNamedItem(name);
        return (n is null) ? null : cast(Attr)n;
    }

    /// This could be used to add all the attributes to a NodeList
    void addAttributes(NodeList nlist)
    {
        auto alen = attributes_.getLength;
        for(uintptr_t i = 0; i < alen; i++)
            nlist ~= attributes_[i];
    }

    /// This could be used to add all the children of this node to a NodeList
    void addChildTags(NodeList nlist)
    {
        if (children_.firstChild_ !is null)
        {
            Node[] nodes = ChildNode.getNodeList(children_.firstChild_);
            nlist ~= nodes;
        }
    }
    /// Add all the child Elements with name to the NodeList argument
    void addChildTags(string name, NodeList nlist)
    {
        ChildNode link	 = children_.firstChild_;

        while (link !is null)
        {
            Element e = cast(Element) link;
            if (e !is null)
            {
                if (cmp(name,e.getTagName())==0)
                    nlist ~= e;
            }
            link = link.next_;
        }
    }

    /// Returns a node list with all the named child elements
    NodeList  getElementsByTagName(string name)
    {
        NodeList result = new NodeList();
        addChildTags(name, result);
        return result;
    }
    /// Namespace implementation has been dropped for now
    NodeList getElementsByTagNameNS(string uri, string local)
    {
        /// this is surely wrong
        string name = (uri is null) ? local : std.conv.text(uri ,":" ,local);
        return getElementsByTagName(name);
    }
    // return all element nodes
    NodeList getChildElements()
    {
        Node[] result;
        ChildNode ch = children_.firstChild_;
        while (ch !is null)
        {
            if (ch.getNodeType() == NodeType.Element_node)
                result ~= ch;
            ch = ch.next_;
        }
        return new NodeList(result);
    }

    /// method
    bool hasAttribute(string name)
    {
        return (attributes_ is null) ? false
               : (attributes_.getNamedItem(name) !is null);
    }
    /// method
    bool  hasAttributeNS(string uri, string local)
    {
        return (attributes_ is null) ? false
               : (attributes_.getNamedItemNS(uri, local) !is null);
    }
    /// Return string value for the named attribute.
    string getAttribute(string name)
    {
        if (attributes_ is null)
            return null;

        Node n = attributes_.getNamedItem(name);
        return ( n is null) ? null : (cast(Attr)n).getValue();
    }
    /// method to be fixed
    string getAttributeNS(string uri, string local)
    {
        if (attributes_ is null)
            return null;
        Node n = attributes_.getNamedItemNS(uri, local);
        return ( n is null) ? null :(cast(Attr)n).getValue();
    }
    /// to be fixed
    Attr getAttributeNodeNS(string uri, string local)
    {
        if (attributes_ is null)
            return null;
        Node n = attributes_.getNamedItemNS(uri, local);
        return ( n is null) ? null : cast(Attr) n;
    }
    /// method
    override string getNodeName()
    {
        return id_;
    }

    string  getTagName()
    {
        return id_;
    }
    /// method
    override NodeList getChildNodes()
    {
        return new NodeList(ChildNode.getNodeList(children_.firstChild_));
    }
    int forEachAttr( NodeVisitFn  dg)
    {
        return (attributes_ is null) ? 0 : attributes_.forEachNode(dg);
    }
    int forEachChild(NodeVisitFn dg)
    {
        ChildNode link = children_.firstChild_;
        int result = 0;
        while (link !is null)
        {
            result = dg(link);
            if (result)
                return result;
            link = link.next_;
        }
        return result;
    }
	/// Brutal replacement of all children with single text node
	override void setTextContent(string txt)
	{
		children_.removeAll();
		if (txt.length > 0)
			appendChild(new Text(txt));
	}
    ///Recursive on Text-like data.  Has no implementation of isTextNodeWhiteSpace
    override const string getTextContent()
    {
        Array!char	app;

        auto xn = cast(ChildNode) children_.firstChild_; // trouble with const
        if (xn is null)
            return null;

        do
        {
            auto n = xn;
            switch(n.getNodeType())
            {
				//case NodeType.Comment_node://
				//case NodeType.Processing_Instruction_node:
            case NodeType.CDATA_Section_node:
            case NodeType.Text_node:
            case NodeType.Element_node:
                app.put(n.getTextContent());
                break;
            default:
                break;
            }
            xn = xn.next_;
        }
        while (xn !is null);

        return app.idup;
    }

	/// Take tree apart.  For work of navigating entire tree, might as 
	/// delete as well.  Used parts of tree should be removed before calling this.
	override void explode(bool del)
	{
		if (attributes_ !is null)
		{
			attributes_.explode(del);
		}
		auto ch = getFirstChild();
		while(ch !is null)
		{
			auto exploder = ch;
			ch = ch.getNextSibling();
			removeChild(exploder);
			exploder.explode(del);
		}
		ownerDoc_ = null;
		assert(children_.empty());
		super.explode(del);
	}
	/// Set the ownerDoc_ member of entire subtree.
    void setDocument(Document d)
    {
        if (ownerDoc_ == d)
            return;

        ownerDoc_ = d;
        ChildNode ch = children_.firstChild_;
        while (ch !is null)
        {
            Element e = cast(Element) ch;
            if (e !is null)
            {
                e.setDocument(d);
            }
            ch = ch.next_;
        }
    }

	/// This is none-DOM, put in because std.xml had it
    @property const string text()
    {
        return getTextContent();
    }
    /// refChild to insert before must already be a child of this element.
    override Node insertBefore(Node newChild, Node refChild)
    {
        ChildNode xref = (refChild !is null) ? cast(ChildNode) refChild : null;
        if (xref !is null && (xref.parent_ != this))
            throw new DOMFail("insertBefore: not a child of this");

        ChildNode xn = cast(ChildNode) newChild;
        if (xn is null)
        {
            DocumentFragment df = cast(DocumentFragment) newChild;
            if (df is null)
                throw new DOMFail("insertBefore: node is not a ChildNode or DocumentFragment");
            Node join = df.getFirstChild();
            if (join is null)
                throw new DOMFail("insertBefore: Empty DocumentFragment");
            Node jend = df.getLastChild();

            ChildNode nbeg = cast(ChildNode)join;
            ChildNode nend = cast(ChildNode)jend;
            if (xref !is null)
            {
                ChildNode.setParent(nbeg,this);
                children_.insertChainBefore(nbeg, nend, xref);
            }
            else
            {
                ChildNode.setParent(nbeg,this);
                children_.chainAppend(nbeg, nend);
            }
            df.clear();
            return newChild;
        }
        else
        {
            if ( xn.parent_ !is null)
                throw new DOMFail("insertBefore: child already has parent");
            if (xref !is null)
            {
                children_.linkBefore(xn, xref);
            }
            else
            {
                children_.linkAppend(xn);
            }
            xn.setParentNode(this);
            return newChild;
        }
    }

    /// Swap out existing child oldChild, with unparented newChild
    override Node replaceChild(Node newChild, Node oldChild)
    {
        ChildNode xnew = cast(ChildNode)newChild;
        ChildNode xold = cast(ChildNode)oldChild;

        if (xold is null || xnew is null)
            throw new DOMFail("replaceChild: null child node");

        if (xnew.parent_ !is null)
            throw new DOMFail("replaceChild: new child already has parent");

        isChildFail(xold);

        ChildNode prior = xold.prev_;
        if (prior !is null)
        {
            prior.next_ = xnew;
        }
        xnew.prev_ = prior;
        ChildNode post = xold.next_;
        if (post !is null)
        {
            post.prev_ = xnew;
        }
        xnew.next_ = post;
        return oldChild;
    }
    /// Throws exception if not a child of this
    override Node  removeChild(Node oldChild)
    {
        ChildNode xold = cast(ChildNode)oldChild;
        if (xold is null)
            throw new DOMFail("null child node for removeChild");
        if (xold.parent_ != this)
            throw new DOMFail("Not a parent of this element");

        children_.removeLink(xold);
        xold.parent_ = null;
        return oldChild;
    }

    /// Relationships can be important
    bool isChild(ChildNode xn)
    {
        return (xn.parent_ == this);
    }

    /// Exception if not my child
    void isChildFail(ChildNode xn)
    {
        if (xn.parent_ != this)
            throw new DOMFail("Not a child node");
    }



    /// Throws exception if child is attached elsewhere

    override Node  appendChild(Node newChild)
    {
        ChildNode xnew = cast(ChildNode) newChild;
        if (xnew is null)
            throw new DOMFail("null child to appendChild");

        children_.linkAppend(xnew);
        xnew.parent_ = this;
        if (ownerDoc_ !is null)
        {
            Element e = cast(Element) xnew;
            if (e !is null)
                e.setDocument(ownerDoc_);
        }
        return newChild;
    }
    void opCatAssign(ChildNode n)
    {
        appendChild(n);
    }
    /// DOM attribute management
    void removeAttribute(string name)
    {
        if (attributes_ is null)
            return;
        Node n = attributes_.removeNamedItem(name);
    }

    /// DOM attribute management
    Attr removeAttributeNode(Attr old)
    {
        if (attributes_ is null)
            return null;
        Node n = attributes_.removeNamedItem(old.getName());
        return ( n is null ) ? null : cast(Attr) n;
    }

    /// DOM attribute management. NS version not working yet
    void removeAttributeNS(string uri, string local)
    {
        if (attributes_ is null)
            return;
        attributes_.removeNamedItemNS(uri,local);
    }

    /// DOM attribute management
    Attr setAttributeNode(Attr sn)
    {
        if (attributes_ is null)
            attributes_ = new NamedNodeMap();
        Node n = attributes_.setNamedItem(sn);
        return ( n is null ) ? null : cast(Attr) n;
    }
    /// DOM attribute management
    void setAttribute(string name, string value)
    {
        Attr na = new Attr(name);
        na.setValue(value);
        setAttributeNode(na);
    }
    /// DOM attribute management. NS version not working yet
    void setAttributeNS(string nsURI, string qualName, string value)
    {
        if (attributes_ is null)
            attributes_ = new  NamedNodeMap();
        Node n = attributes_.getNamedItemNS(nsURI, qualName);
        if (n is null)
        {
            Attr nat = new  AttrNS(nsURI, qualName);
            nat.setValue(value);
            nat.setOwner(this);
        }
        else
        {
            Attr nat = cast(Attr)n;
            nat.setValue(value);
        }
    }
    override Node getFirstChild()
    {
        return children_.firstChild_;
    }
    override Node getLastChild()
    {
        return children_.lastChild_;
    }



};

/// Seems to work ok
class AttrNS :  Attr
{
protected:
    string uriNS_;
    string localName_;

    package void setIdentity(string nsURI, string name)
    {
        id_ = name;
        uriNS_ = nsURI;
        auto pos = id_.indexOf(':');
        localName_ = (pos >= 0) ? id_[pos+1..$] : id_;
    }

    package void setURI(string nsURI)
    {
        uriNS_ = nsURI;
    }

public:
    /// construct
    this(string name)
    {
        setIdentity(null, name);
    }
    /// constructed with its associated namespace
    this(string nsURI, string name)
    {
        setIdentity(nsURI, name);
    }
    /// return the identifying namespace URI
    override string getNamespaceURI()
    {
        return uriNS_;
    }
    /// The bit after the prefix
    override string getLocalName()
    {
        return localName_;
    }
    /// return the prefix
    override string getPrefix()
    {
        auto poffset = id_.length - localName_.length;
        return  (poffset > 0) ? id_[0..poffset-1] : "";
    }

};

/// DOM attribute class with name and value
class Attr : Node
{
protected:
    string value_;
    Element   owner_;
    //uint	  flags_;

    enum
    {
        isSpecified = 1,
    };
public:
    this()
    {
    }

    /// Construct
    this(string name)
    {
        super();
        id_ = name;
    }
    /// Construct
    this(string name, string value)
    {
        super();
        id_ = name;
        value_ = value;
    }

    /// Property
    override const NodeType getNodeType()
    {
        return NodeType.Attribute_node;
    }
    /// attribute name
    override string getNodeName()
    {
        return id_;
    }
    /// attribute value
    override string getNodeValue()
    {
        return value_;
    }
    /* forgot what this is for
    bool getSpecified() { return (flags_ & isSpecified) != 0; }*/

    /// Property
    void setOwner(Element e)
    {
        owner_ = e;
    }

	override void explode(bool del)
	{
		owner_ = null;
		super.explode(del);
	}
    /// Property
    final Element getOwnerElement()
    {
        return owner_;
    }
    /// Property
    final string getValue()
    {
        return value_;
    }
    /// Property
    final void setValue(string val)
    {
        value_ = val;
    }
    /// Property
    final string getName()
    {
        return id_;
    }
}

/// Abstract class for all Text related Nodes, Text, CDATA, Comment
abstract class CharacterData :  ChildNode
{
public:

    /// construct with data
    this(string data)
    {
        super(data);
    }

    /// add data
    void appendData(string s)
    {
        id_ ~= s;
    }
    /// delete selected part of data
    void deleteData(int offset, int count)
    {
        id_ = text(id_[0..offset],id_[offset+count..$]);
    }
    /// return  data
    string getData()
    {
        return id_;
    }
    /// set  data
    void  setData(string s)
    {
        id_ = s;
    }
    /// property of content
    @property final size_t length()
    {
        return id_.length;
    }
    /// sneak in data
    void insertData(int offset, string s)
    {
        id_ = text(id_[0..offset],s,id_[offset..$]);
    }
    /// stomp on data
    void replaceData(int offset, int count, string s)
    {
        id_ = text(id_[0..offset], s, id_[offset+count..$]);
    }
    /// Has text, so get it
    override string getTextContent()
    {
        return id_;
    }
	/// Takes text, so set it
	override void setTextContent(string txt)
	{
		id_ = txt;
	}

};

/** Text child of XML elements */
class Text :  CharacterData
{
public:
    this(string s)
    {
        super(s);
    }

    override const NodeType getNodeType()
    {
        return NodeType.Text_node;
    }

    /// Split to put things in between
    Text splitText(int offset)
    {
        string d2 = id_[offset .. $];

        id_ = id_[ 0.. offset];

        Text t = new Text(id_);
        //t.setDocument(ownerDoc_);
        Node p = getParentNode();
        if (p)
        {
            Element pe = cast(Element)p;
            if (pe !is null)
            {
                Node nx = p.getNextSibling();
                if (nx !is null)
                    pe.insertBefore(t, nx);
                else
                    pe.appendChild(t);
                t.setParentNode(p);
            }
        }
        return t;
    }
    /// D object property
    override const string toString()
    {
        return id_;
    }

}

/// DOM item
class CDATASection :  Text
{
public:
    this(string data)
    {
        super(data);
    }

    override const NodeType getNodeType()
    {
        return NodeType.CDATA_Section_node;
    }

    override const string toString()
    {
        return makeXmlCDATA(id_);
    }
};


/// DOM item
class Comment :  CharacterData
{
public:
    this(string data)
    {
        super(data);
    }

    override const NodeType getNodeType()
    {
        return NodeType.Comment_node;
    }

    override const string toString()
    {
        return makeXmlComment(id_);
    }
};

class IdNode  :  Node
{
private:
    EntityData	data_;
public:
    @property final EntityData	entityData()
    {
        return data_;
    }
	this(EntityData def)
	{
		id_ = def.name_;
		data_ = def;
	}
    override string getNodeName()
    {
        return id_;
    }

    string getPublicId()
    {
        return data_.src_.publicId_;
    }
    string getSystemId()
    {
        return data_.src_.systemId_;
    }

    const string externalSource()
    {
        char[] result;
        auto app = appender(result);
		auto publicId = data_.src_.publicId_;
		auto systemId = data_.src_.systemId_;

        void addqt(string n, string v)
        {
            app.put(n);
            app.put(" \'");
            app.put(v);
            app.put('\'');
        }

        if (publicId.length > 0)
        {
            addqt("PUBLIC",publicId);
            if (systemId.length > 0)
                addqt("",systemId);
        }
        else if (systemId.length > 0)
            addqt("SYSTEM" ,systemId);
        result = app.data();
        return assumeUnique(result);
    }
}



/// DOM node type for entity, a supplement to xmlp.xmlp.linkdom, becase EntityData is defined elsewhere.
class Entity : IdNode
{
public:

    this(EntityData def)
    {
		super(def);
    }

    override string getNodeValue()
    {
        return data_.value_;
    }
    override string getPublicId()
    {
        return data_.src_.publicId_;
    }
    override string getSystemId()
    {
        return data_.src_.systemId_;
    }

    string getNotationName()
    {
        return data_.ndataref_;
    }
    string getXmlEncoding()
    {
        return data_.encoding_;
    }
    string getInputEncoding()
    {
        return data_.encoding_;
    }
    string getXmlVersion()
    {
        return data_.version_;
    }

    override const NodeType getNodeType()
    {
        return NodeType.Entity_node;
    }
}



class Notation : IdNode
{
	this(EntityData def)
	{
		super(def);
	}

    override const	NodeType getNodeType ()
    {
        return NodeType.Notation_node;
    }

    override const   string toString()
    {
        return text("<!NOTATION ",id_,' ', externalSource(),">");
    }
}

void printDocType(DocumentType dtd, XmlPrinter tp)
{

    NamedNodeMap nmap = dtd.getNotations();
    if (nmap.getLength > 0)
    {
        auto putOut = tp.options.putDg;
        Array!char output;
        output.put("<!DOCTYPE ");
        output.put(dtd.getNodeName());
        output.put(" [");
        immutable putline = tp.options.noWhiteSpace;//crazy canonical compatible
        if (putline)
            output.put('\n');
        putOut(output.toArray);

        foreach(n ; nmap)
        {
            output.length = 0;
            auto note = cast(Notation) n;
            output.put(n.toString());
            if (putline)
                output.put('\n');
            putOut(output.toArray);
        }
        output.length = 0;
        output.put("]>");
        if (putline)
            output.put('\n');
        putOut(output.toArray);
    }
}

void printLinked(Node n, XmlPrinter tp)
{
    while(n !is null)
    {
        NodeType nt = n.getNodeType();
        switch(nt)
        {

        case NodeType.Element_node:
            printElement(cast(Element)n, tp);
            break;
        case NodeType.Comment_node:
            if (tp.noComments)
                break;
        goto case NodeType.CDATA_Section_node;
        case NodeType.CDATA_Section_node:
            tp.putIndent(n.toString());
            break;
        case NodeType.Processing_Instruction_node:
        goto case NodeType.CDATA_Section_node;
        case NodeType.Document_type_node:
            // only output if have notations;
            printDocType(cast(DocumentType) n, tp);
            break;
        default:
            string txt = encodeStdEntity(n.toString(), tp.options.charEntities);
            tp.putIndent(txt);
            break;
        }
        n = n.getNextSibling();
    }
}

void printDocument(Document d, StringPutDg putOut, uint indent)
{
    auto  opt = XmlPrintOptions(putOut);



    DOMConfiguration config = d.getDomConfig();
    Variant v = config.getParameter("canonical-form");
    bool canon = v.get!(bool);
    opt.xversion = to!double(d.getXmlVersion());


    opt.indentStep = indent;

    if (canon)
    {
        opt.emptyTags = false;
        opt.noComments = true;
        opt.noWhiteSpace = true;
    }


    auto tp = XmlPrinter(opt,indent);
    if (!canon || (opt.xversion > 1.0))
    {
        AttributeMap attributes;
		attributes.appendMode = true;
        attributes["version"] = d.getXmlVersion();
        if (!canon)
        {
            attributes["standalone"] = d.getXmlStandalone() ? "yes" : "no";
            attributes["encoding"] = d.getXmlEncoding(); // this may not be valid, since its utf-8 string right here.
			attributes.sort();
        }
        //
        printXmlDeclaration(attributes, putOut);
    }
    Node n = d.getRootElement();
    if (n !is null)
        n = n.getFirstChild();
    if (n !is null)
    {
        printLinked(n, tp);
    }
}

void printElement(Element e, XmlPrinter tp)
{
    bool hasChildren = e.hasChildNodes();
    bool hasAttributes = e.hasAttributes();

    auto putOut = tp.options.putDg;

    string tag = e.getTagName();
    AttributeMap smap;
    if (hasAttributes)
        smap = toAttributeMap(e);

    if (!hasChildren)
    {
        tp.putStartTag(tag, smap, true);
        return;
    }

    Node firstChild = e.getFirstChild();

    if ((firstChild.getNextSibling() is null) && (firstChild.getNodeType() == NodeType.Text_node))
    {
        tp.putTextElement(tag, smap, firstChild.getNodeValue());
        return;
    }

    tp.putStartTag(tag,smap,false);
    auto tp2 = XmlPrinter(tp);
    printLinked(firstChild, tp2);
    tp.putEndTag(tag);
}


/** Keeps track of active namespace definitions by holding the AttrNS by prefix, or null for default.
	Each time a new definition is encountered a new NameSpaceSet will be stacked.
*/
class  NameSpaceSet
{
version(GC_STATS)
{
	mixin GC_statistics;
	static this()
	{
		setStatsId(typeid(typeof(this)).toString());
	}
}
    NameSpaceSet	parent_;

    AttrNSMap		nsdefs_;	 // namespaces defined by <id> or null for default
    ElementNS		elem_;

    /// construct
    this(ElementNS e, NameSpaceSet nss)
    {
        elem_ = e;
        parent_ = nss;
        // start with all of parents entries
        if (parent_ !is null)
        {
            foreach(k,v ; parent_.nsdefs_)
            {
                nsdefs_[k] = v;
            }
        }
		version(GC_STATS)
			gcStatsSum.inc();
    }

    /// return attribute holding URI for prefix
    AttrNS getAttrNS(string nsprefix)
    {
        auto pdef = nsprefix in nsdefs_;
        return (pdef is null) ? null : *pdef;
    }

}

/// Return AttributeMap (whatever it is), from DOM element
AttributeMap toAttributeMap(Element e)
{
    AttributeMap result;
    NamedNodeMap atmap = e.getAttributes();

	version(CustomAA)
	{
    result.capacity(atmap.getLength());
	}

    if (atmap !is null)
    {
        for(uintptr_t i = 0; i < atmap.getLength; i++)
        {
            Attr atnode = cast(Attr)atmap.item(i);
			result.put(AttributeMap.BlockRec(atnode.getName(),atnode.getValue()));
        }
		//TODO: result is already sorted?
    }
    return result;
}

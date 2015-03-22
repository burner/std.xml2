/**

Authors: Michael Rynn
Licence: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Distributed under the Boost Software License, Version 1.0.


Able to parse XML that uses a DTD.
It creates a DTDValidate object, which might be used to validate other XML documents, although
this has not been specifically setup. TODO: Needs a mechanism to compare source identity, such as filename,
so then no need to re-parse the DTD.

*/

module xmlp.xmlp.doctype;

//import std.xmlp.linkdom;
import xmlp.xmlp.error;
import xmlp.xmlp.parseitem;

import xmlp.xmlp.subparse;
import xmlp.xmlp.charinput;
import xmlp.xmlp.xmlchar;
//import std.xmlp.source;
import alt.zstring;
import xmlp.xmlp.entity;
import xmlp.xmlp.feeder;
import std.stream;
import std.utf;
import std.string;
import std.array;
import std.exception;
import std.conv;
import std.path;
import std.file;
import std.variant;
import xmlp.xmlp.dtdtype;
import xmlp.xmlp.xmlparse;
import xmlp.xmlp.entitydata;
import xmlp.xmlp.dtdvalidate;
debug
{
    import std.stdio;
}
/** Most of the methods are protected. Access is through CoreParser methods.
	A lot of validation has been moved to the std.xmlp.dtdtype.DTDValidate class.
*/
class XmlDtdParser : XmlParser
{
protected:
    enum DocEndType { noDocEnd, singleDocEnd, 	doubleDocEnd }; // "", "]" or "]]>"
    //Document		doc_;
    //DTDValidate		dtd_;
    //IDValidate		idValidate;
public:


    /// An empty document to build
    this(DataFiller df, bool doValidate)
    {
        super(df);
        //doc_ = d;
        validate_ = doValidate; // turn on switches for validation in CoreParser
        //readDocConfiguration();
		//onProcessingInstruction_ = &internalProcessInstruction;
    }
	/+
    void readDocConfiguration()
    {
        DOMConfiguration config = doc_.getDomConfig();

        Variant v = config.getParameter("namespaces");
        namespaceAware_ = v.get!(bool);
        v = config.getParameter("edition");
        maxEdition = v.get!uint();
    }
	+/
    void DTD(DTDValidate dtd)
    {
        dtd_ = dtd;
    }

    DTDValidate DTD()
    {
        return dtd_;
    }


    override void setXMLVersion(double val)
    {
        if (isEntity)
        {
            if (val < docVersion_)
            {
                return;
            }
            else
            {
                if (val > docVersion_)
                {
                    super.setXMLVersion(val);
                }
            }
        }
        else
            super.setXMLVersion(val);
    }

    @property
    package void validateIDREF(bool val)
    {
        if (val && (idValidate_ is null))
            idValidate_ = new IDValidate();
    }
    /// return parsed External Entity content on behalf of another parser, whose properties are therefore significant
    string parseSystemEntity(IXMLParser vp)
    {
        setXMLVersion(vp.xmlVersion());
        isEntity = true;
        master_ = vp;
            // set prepareThrow handler
        setPrepareThrowDg(vp.getPrepareThrowDg());
            // if looking an entity, maybe check if current context is entity
        string[]	paths;

        if (vp.inParamEntity())
        {
            paths ~= vp.entityContext().baseDir_;
        }
        paths ~= vp.systemPaths();
        systemPaths_ = paths;

        pumpStart();
        frontFilterOn();
        if (matchInput("<?xml"d))
        {
            markupDepth_++;
            XmlReturn iret;
            doXmlDeclaration(iret);
        }
        string result;
        textReplaceCharRef(result);
        return result;
    }
    bool processExternalDTD(IXMLParser vp, DTDValidate primaryDtd)
    {
        bool wasInternal = primaryDtd.isInternal_;

        isStandalone_ = false;
        setXMLVersion(vp.xmlVersion());
        master_ = vp;
        isEntity = true;
        setPrepareThrowDg(vp.getPrepareThrowDg());
        setReportInvalidDg(vp.getReportInvalidDg());
        systemPaths(vp.systemPaths());
        dtd_ = primaryDtd;
		dtd_.isInternal_ = false;
        constructDocType(DocEndType.noDocEnd);
        primaryDtd.isInternal_ = wasInternal;
        return true;
    }


protected:
    /// adjust bracket count for ]
    bool isCloseSquare()
    {
        dchar test;
        if (!empty && front==']')
        {
            popFront();
            squareDepth_--;
            return true;
        }
        return false;
    }
    /// adjust bracket count for [
    final bool isOpenSquare()
    {
        dchar test;
        if (!empty && front=='[')
        {
            squareDepth_++;
            popFront();
            return true;
        }
        return false;
    }


    bool matchMarkup(dchar match)
    {
        if (empty)
            return false;
        if (front == match)
        {
            switch(match)
            {
            case '>':
                markupDepth_--;
                break;
            case '<':
                markupDepth_++;
                break;
            default:
                break;
            }
            popFront();
            return true;
        }
        else
            return false;
    }

    final bool matchParen(dchar poc)
    {
        if (!empty && (front == poc))
        {
            switch(poc)
            {
            case '(':
                parenDepth_++;
                break;
            case ')':
                parenDepth_--;
                break;
            default:
                break;
            }
            popFront();
            return true;
        }
        return false;
    }




    override bool fetchEntityData(string ename, bool isAttribute, ref EntityData ed)
    {
        if (dtd_ is null)
			doUnknownEntity(ename);
           //return false;

        auto ge = dtd_.getEntity(ename);
        //auto pge = ename in dtd_.generalEntityMap;
        if (ge is null)
        {
            if (dtd_.undeclaredInvalid_ && !isAttribute)
            {
                if (validate_ )
                {
                    estk_.pushMsg(text("referenced undeclared entity ", ename),ParseError.invalid);
                    reportInvalid();
                }
                // create EntityReference and pass it upwards ?
                //value = text('&',ename,';');
                return false; // stop recursive lookup!
            }
            else
                doUnknownEntity(ename);
        }
        ed = ge;

        if (ge.status_ == EntityData.Expanded)
            return true;

        StringSet eset;

        int reftype = RefTagType.UNKNOWN_REF;
        string value;
        if (!lookupReference(ge.name_, value, eset, reftype))
        {
            doNotWellFormed(text("Error in entity lookup: ", ge.name_));
        }
        if (reftype==RefTagType.NOTATION_REF)
        {
            doNotWellFormed(text("Reference to unparsed entity ",ename));
        }
        if(isAttribute && this.isStandalone_ && reftype==RefTagType.SYSTEM_REF)
            doNotWellFormed("External entity in attribute of standalone document");
        return true;
    }

    // General entity to be decoded in the parse stream
    /+override public bool decodeEntityReference(string ename, bool isAttribute)
    {
        string value;
        EntityData ed;
        if (fetchEntityData(ename, isAttribute, ed))
        {
            if (ed.value_.length > 0)
            {
                doPushContext(ed.value_,false,ed);
            }
            return true;
        }
        else
        {
            return false;
        }
    }
	+/
    /// Stop when not uppercase
    protected final bool getUpperCaseName(ref string wr)
    {
        scratch_.length = 0;

        while(!empty && (front <= 'Z') && (front >= 'A'))
        {
            scratch_.put(front);
            popFront();
        }
        if (scratch_.length > 0)
        {
            wr = scratch_.idup;
            return true;
        }
        return false;
    }


    /** fill in the entity.value and set entity.Expanded if valid
    	digest and return the value
     This code is not properly understood. It kind of grew.
    */
    private bool deriveEntityContent(EntityData entity, StringSet stk, out int reftype)
    {

        bool assignEmpty()
        {
            entity.status_ = EntityData.Expanded;
            entity.value_ = null;
            return true;
        }

        if (isStandalone_)
        {
            if (!entity.isInternal_) // w3c test sun  not-wf-sa03
            {
                estk_.pushMsg("Standalone yes and referenced external entity",ParseError.error);
                return false;
            }

        }
        if (entity.status_ == EntityData.Expanded)
        {
            reftype = entity.reftype_;
            return true;
        }
        if (entity.status_ < EntityData.Found)
        {
            if (entity.ndataref_.length > 0) // get the notation
            {
                reftype = RefTagType.NOTATION_REF;
                auto n = dtd_.notationMap.get(entity.ndataref_,null);
                if (n is null)
                {
                    if (validate_)
                        estk_.pushMsg(text("Notation not declared: ", entity.ndataref_),ParseError.invalid);
                    entity.status_ = EntityData.Failed;
                    return true; // need to check replaced flag!
                }
                else
                {
                    // TODO: what do do with notations?
                    entity.status_ = EntityData.Expanded;
                    return true;
                }
            }
            else if (entity.src_.systemId_ !is null)
            {
                reftype = RefTagType.SYSTEM_REF;

                // read the contents
                auto sys_uri = entity.src_.systemId_;
                if (sys_uri.length > 0) // and not resolved?
                {
                    string esys;
                    string baseDir;
                    if (!getSystemEntity(sys_uri, esys, baseDir))
                    {
                        estk_.pushMsg("DTD System Entity not found",ParseError.error);
                        entity.status_ = EntityData.Failed;
                        return false;
                    }
                    if (esys.length > 0)
                    {
                        entity.isInternal_ = false;
                        entity.baseDir_ = baseDir;
                        entity.value_ = esys;
                        entity.status_ = EntityData.Found;
                    }
                    else
                    {
                        return assignEmpty();
                    }
                }
                else
                {
                    estk_.pushMsg("DTD SYSTEM uri missing",ParseError.error);
                    return false;
                }
            }
            else
            {
                return assignEmpty();
            }
        }
        // for checking well formed for standalone=yes,
        // need to fail if the original entity was internal

        if (entity.status_ == EntityData.Found) // can be empty!
        {
            if (!stk.put(entity.name_))
            {
                reftype = RefTagType.ENTITY_REF;
                estk_.pushMsg(text("recursion in entity lookup for ", entity.name_),ParseError.error);
                return false;
            }
            string tempValue;
            if (entity.value_.length > 0)
            {
                {
					doPushContext(entity.value_, true, null);
                    scope(exit)
						doPopContext();
                    if (!textReplaceCharRef(tempValue))
                        return false;
                }
                StringSet eset;

                if (inDTD() && !textReplaceEntities(entity.isInternal_, tempValue, tempValue,eset))
                {
                    estk_.pushMsg("parsed entity replacement failed",ParseError.error);
                    return false;
                }
				doPushContext(tempValue, true, entity);
				scope(exit)
					doPopContext();

                if (!expandEntityData(tempValue, stk, reftype))
                {
                    estk_.pushMsg("ENTITY value has bad or circular Reference",ParseError.error);
                    return false;
                }
                if (reftype == RefTagType.SYSTEM_REF)
                    entity.isInternal_ = false;
            }

            entity.value_ = tempValue;
            entity.status_ = EntityData.Expanded;
            stk.remove(entity.name_);
            return true;
        }
        return false;
    }



    /** Actual lookup from entity reference. Error if entity not replaced
     Validation has this notion that standalone yes means no need for external definitions.
     But a definition can be contaminated from an external source by a parameter entity
     as part of the definition.
     Trying to setup up reftype here, so that any hint of SYSTEM reference in the recursive definition
     falsifies isInternal in the final result.
    	*/

    bool lookupReference(string domName, out string value, StringSet stk, out int reftype)
    {
        if (dtd_ is null)
            return false;
		/*
        //DocumentType doct = dtd_.docTypeNode_;
       // NamedNodeMap map = doct.getEntities();
       // Node n = map.getNamedItem(domName);

        if (n !is null)
        {
            Entity xe = cast(Entity) n;
            reftype = (xe.getSystemId() is null) ?  RefTagType.ENTITY_REF :  RefTagType.SYSTEM_REF;
            value =  xe.getNodeValue();
            return true;
        }
		*/
        EntityData entity = dtd_.getEntity(domName);

        if (entity is null)
        {
            reftype = RefTagType.UNKNOWN_REF;
            return false;
        }
        if (entity.status_ == EntityData.Expanded)
        {
            value = entity.value_;
            reftype = entity.reftype_;
            return true;
        }

        if (! deriveEntityContent(entity, stk, reftype))
            return false;

        switch(reftype)
        {
        case RefTagType.SYSTEM_REF:
            entity.isInternal_ = false;
            break;
        case RefTagType.NOTATION_REF:
            if (isInGeneralEntity)
                throwParseError(format("Referenced unparsed data in entity %s", this.entity_.name_));

            entity.isInternal_ = false;
            entity.status_ = EntityData.Expanded;
            entity.reftype_ = cast(RefTagType) reftype;
            break;
        default:
            break;
        }

        if (entity.status_ == EntityData.Expanded)
        {
            //Entity xe = new Entity(entity);
            //map.setNamedItem(xe);
            value = entity.value_;
            return true;
        }
        else
        {
            estk_.pushMsg(text("Value cannot be determined for entity: ",entity.name_),ParseError.error);
            return false;
        }
    }
    /// Fetch and digest these entities
    private void verifyGEntity()
    {
        //if (dtd_.GEntityMap.length > 0)
        string testGEValue;
        StringSet eset;
        foreach(ge ; dtd_.generalEntityMap)
        {
            int eStatus = ge.status_;
            if (eStatus > EntityData.Unknown && eStatus < EntityData.Expanded)
            {
                if (!this.isStandalone_ || ge.isInternal_)
                {
                    int reftype = RefTagType.UNKNOWN_REF;
                    eset.clear();
                    if (!lookupReference(ge.name_, testGEValue, eset, reftype))
                    {
                        throwNotWellFormed(text("Error in entity lookup: ", ge.name_));
                    }
                }
            }
            else if (ge.ndataref_.length > 0)
            {
                if (ge.isInternal_)
                {
                    int reftype =  RefTagType.UNKNOWN_REF;
                    eset.clear();
                    if (eStatus > EntityData.Unknown && eStatus < EntityData.Expanded )
                    {
                        if (!deriveEntityContent(ge, eset, reftype))
                            throwNotWellFormed(text("Error in entity ",ge.name_));
                    }
                }
            }
        }
    }



    /// fetch external DTD declarations
    bool parseExternalDTD(ExternalDTD edtd)
    {
        string uri;

        if (!getSystemPathImpl(edtd.src_.systemId_, uri))
            return false;

        auto s = new BufferedFile(uri);
        auto sf = new XmlStreamFiller(s);

        auto dtp = new XmlDtdParser(sf,validate_);
        return dtp.processExternalDTD(this, dtd_ );
    }


    /// Get the Notation name
    private bool parseDtdNotation()
    {
        int spacect = munchSpace();

        //string noteName;

        if (!super.getXmlName(entityName_))
        {
            estk_.pushMsg("Notation must have a name",ParseError.fatal);
            return false;
        }
        auto checkName = entityName_.toArray;
        bool hasIllegalColon =  (namespaceAware_ && (indexOf(checkName,':') >= 0));


        if (hasIllegalColon)
            estk_.pushMsg("Notation name with ':' in namespace aware parse",ParseError.fatal);

        if (spacect == 0)
            throwErrorCode(ParseErrorCode.MISSING_SPACE);

        if (validate_)
        {
            auto pnode = checkName in dtd_.notationMap;
            if (pnode !is null)
            {
                //  already have error?, so ignore
            }
        }
        if (hasIllegalColon) //
            return false;

        spacect = munchSpace();
        ExternalID extsrc;

        string noteName = checkName.idup;
        if (getExternalUri(extsrc))
        {

            if (spacect == 0)
                throwErrorCode(ParseErrorCode.MISSING_SPACE);
			/*
            Notation xnote = new Notation();
            xnote.id_ = noteName.idup;
            xnote.publicId = extsrc.publicId_;
            xnote.systemId = extsrc.systemId_;
            auto nmap = dtd_.docTypeNode_.getNotations();
            nmap.setNamedItem(xnote);
			*/
			auto xnote = new EntityData(noteName,EntityType.Notation);
			xnote.src_ = extsrc;

            dtd_.notationMap[noteName] = xnote;


            //dtd_.addNotation(new xdom.DtdNotation(idname, extsrc));
        }
        else
        {
            estk_.pushMsg("NOTATION needs PUBLIC or SYSTEM id",ParseError.fatal);
            return false;
        }
        munchSpace();
        if (empty || front != '>')
        {
            estk_.pushMsg(getErrorCodeMsg(ParseErrorCode.MISSING_END_BRACKET));
            return false;
        }
        markupDepth_--;
        popFront();
        return true;
    }
    /// Child element counting
    bool getOccurenceCharacter(ref ChildOccurs occurs)
    {
        // check for + or *.

        if (empty)
            return false;

        switch(front)
        {
        case '*':
            occurs = ChildOccurs.oc_zeroMany;
            break;
        case '+':
            occurs = ChildOccurs.oc_oneMany;
            break;
        case '?':
            occurs = ChildOccurs.oc_zeroOne;
            break;
        default:
            occurs = ChildOccurs.oc_one;
            return true; // no pop
        }
        popFront();
        return true;
    }
    /// List of child elements for ELEMENT declaration
    uint collectElementList(ElementDef def, ChildElemList plist, bool terminator = true)
    {
        // go until matching ')'

        string ename;

        ChildSelect sep = ChildSelect.sl_one;

        //ParseInput src = ctx_.in_;

        uint errorExpectSeparator()
        {
            return estk_.pushMsg("Expected separator in list",ParseError.fatal);
        }
        uint matchSeparator()
        {
            if (empty)
                return 0;

            switch(front)
            {
            case '|':
                if (sep != ChildSelect.sl_choice)
                {
                    if (sep == ChildSelect.sl_one)
                    {
                        sep = ChildSelect.sl_choice;
                        plist.select = sep;
                    }
                    else
                        return inconsistent_separator(sep);
                }
                break;
            case ',':
                if (sep != ChildSelect.sl_sequence)
                {
                    if (sep == ChildSelect.sl_one)
                    {
                        sep = ChildSelect.sl_sequence;
                        plist.select = sep;
                    }
                    else
                        return inconsistent_separator(sep);
                }
                break;
            default:
                // not a separator
                return false;

            }
            popFront();
            return true;
        }

        int namect = 0;
        int defct = 0;
        bool mixedHere = false;
        bool expectSeparator = false;
        bool expectListItem = false; // true if after separator

        bool endless = true;
        while(endless)
        {
            munchSpace();
            if (matchParen(')'))
            {

                if (defct == 0)
                {
                    return estk_.pushMsg("empty definition list",ParseError.fatal);
                }
                if (expectListItem)
                {
                    return estk_.pushMsg("expect item after separator",ParseError.fatal);
                }
                getOccurenceCharacter(plist.occurs);
                if (mixedHere)
                {
                    if (def.hasElements)
                    {
                        if (plist.occurs != ChildOccurs.oc_zeroMany)
                        {
                            return estk_.pushMsg("mixed content can only be zero or more",ParseError.fatal);
                        }
                    }
                    else
                    {
                        if ((plist.occurs != ChildOccurs.oc_one) && (plist.occurs != ChildOccurs.oc_zeroMany) )
                        {
                            return estk_.pushMsg("pure Parsed Character data has bad occurs modifier",ParseError.fatal);
                        }
                    }
                }
                break;
            }
            else if (expectSeparator && matchSeparator())
            {
                expectSeparator = false;
                expectListItem = true;
                continue;
            }
            if (matchParen('('))
            {

                if (expectSeparator)
                {
                    return errorExpectSeparator();
                }
                if (def.hasPCData)
                {
                    return estk_.pushMsg("Content particles defined in mixed content",ParseError.fatal);
                }
                expectListItem = false;
                ChildElemList nlist = new ChildElemList();
                plist.addChildList(nlist);
                if ( collectElementList(def,nlist,true) > 0)
                    return false;
                defct += plist.length;
                expectSeparator = true;
                continue;
            }


            if (empty)
            {
                if (terminator)
                    ThrowEmpty();
                return 0;
            }

            string keyword;

            switch(front)
            {
            case '#':
                popFront();
                if (expectSeparator)
                    return errorExpectSeparator();

                if (!getUpperCaseName(keyword))
                    throwNotWellFormed("Keyword expected");

                if (keyword == "PCDATA")
                {
                    def.hasPCData = true;
                    mixedHere = true;
                    if ((namect > 0) || (plist.parent !is null))
                    {
                        return estk_.pushMsg("#PCDATA needs to be first item",ParseError.fatal);
                    }
                }
                else
                {
                    return estk_.pushMsg(format("unknown #",ename),ParseError.fatal);
                }
                defct++;
                expectSeparator = true;
                expectListItem = false;
                break;
            case '%':
                popFront();
                if (!pushEntityContext())
                    return false;
                if (dtd_.isInternal_)
                {
                    popContext();
                    return estk_.pushMsg("Parsed entity used in internal subset definition",ParseError.fatal);
                }
                break;
            default:
                //expect a name
                if (expectSeparator)
                {
                    return errorExpectSeparator();
                }

                if (!getXmlName(tagScratch_))
                {
                    return estk_.pushMsg("element name expected",ParseError.fatal);
                }
                /*if (checkName == "CDATA")
                {
                	// test case not-wf-sa-128. Why cannot CDATA be element name?
                	return push_error("invalid CDATA");
                }
                * */
                expectListItem = false;

                string checkName = tagScratch_.idup;
                ChildId child = new ChildId(checkName);
                getOccurenceCharacter(child.occurs);
                if (def.hasPCData && (child.occurs!=ChildOccurs.oc_one))
                {
                    return estk_.pushMsg("Content particle not allowed with PCData",ParseError.fatal);
                }
                if ((plist.firstIndexOf(checkName) >= 0) && (sep == ChildSelect.sl_choice))
                {

                    if (mixedHere)
                    {
                        if (validate_)
                            estk_.pushMsg("Mixed content and repeated choice element",ParseError.invalid);
                    }
                    else
                        return estk_.pushMsg("Duplicate child element name in | list",ParseError.error); //E34
                }
                else
                    plist.append(child);
                defct++;
                if (namect==0)
                {
                    def.hasElements = true;
                }
                namect++;
                expectSeparator = true;
            }
        }
        return 0;
    }

    /// another error type
    uint inconsistent_separator(dchar val)
    {
        return estk_.pushMsg(format("inconsistent separator %x" ,val),ParseError.invalid);
    }
    ///  Accumulate Error report
    private uint getNoSpaceError()
    {
        return estk_.pushMsg(("needs a space"),ParseError.fatal);
    }
    /// DTD ELEMENT declaration
    uint parseDtdElement()
    {
        uint duplicate_def()
        {
            return estk_.pushMsg(("Duplicate definition"),ParseError.fatal);
        }
        // has a name
        //ParseInput src = ctx_.in_;
        string dfkey;
        munchSpace();

        if (!getXmlName(entityName_))
            throwErrorCode(ParseErrorCode.EXPECTED_NAME);

        if (!munchSpace())
        {
            estk_.pushMsg(getErrorCodeMsg(ParseErrorCode.MISSING_SPACE),ParseError.fatal);
            throw getBadCharError(front);
        }
        string ename = entityName_.idup;
        ElementDef def = dtd_.getElementDef(ename);

        if (def is null)
        {
            def = new ElementDef(ename);
            dtd_.addElementDef(def);
        }
        else
        {
            if (validate_)
                estk_.pushMsg(text("Element already declared: " ,ename),ParseError.invalid);
        }
        def.isInternal = dtd_.isInternal_;

        // see if attributes defined for element already

        AttributeList attList = dtd_.getAttributeList(ename);

        if (attList !is null)
            def.attributes = attList;

        int listct = 0;
        while (!empty)
        {
            munchSpace();

            if (matchParen('('))
            {

                if (listct > 0)
                    return duplicate_def();
                if (def.list is null)
                    def.list = new ChildElemList();
                if ( collectElementList(def, def.list, true) > 0)
                    return estk_.errorStatus;
                listct++;

                continue;
            }
            if (!empty && front=='>')
            {
                markupDepth_--;
                popFront();

                if (listct==0)
                {
                    throwNotWellFormed("sudden end to list");
                }

                break;
            }
            if (matchInput("EMPTY"d))
            {
                // mark empty
                if (listct > 0)
                    return duplicate_def();
                def.hasElements = false;
                def.hasPCData = false;
                def.hasAny = false;
                listct++;
            }
            else if (matchInput("ANY"d))
            {
                if (listct > 0)
                    return duplicate_def();
                def.hasElements = true;
                def.hasPCData = true;
                def.hasAny = true;
                listct++;
            }
            else if (!empty && front == '%')
            {
                popFront();
                pushEntityContext();
            }
            else
            {
                if (empty)
                    ThrowEmpty();
                return estk_.pushMsg(format("Unexpected character %x",front),ParseError.fatal);
            }
        }

        return 0;
    }
    /// validate the Entity syntax
    /+
[Definition: For an internal entity, the replacement text is the content of the entity,
     after replacement of character references and parameter-entity references.]
[Definition: For an external entity, the replacement text is the content of the entity,
     after stripping the text declaration (leaving any surrounding whitespace)
     if there is one but without any replacement of character references or parameter-entity references.]

        The literal entity value as given in an internal entity declaration (EntityValue)
        may contain character, parameter-entity, and general-entity references.
        Such references MUST be contained entirely within the literal entity value.

        The actual replacement text that is included (or included in literal)
        as described above MUST contain the replacement text of any parameter entities referred to,
           and MUST contain the character referred to, in place of any character references in the literal entity value;
    however, general-entity references MUST be left as-is, unexpanded.
    +/
    void verifyEntitySyntax(string s, bool isPE)
    {
        /* save previous context entity values */

        bool srcExternalEntity = this.inParamEntity();
        if (srcExternalEntity)
            srcExternalEntity = !entityContext().isInternal_;

        auto pp = contextPopper(this,s);


        void bombWF_Internal(string val)
        {
            throwNotWellFormed(text("Parameter Entity in ", val, " declared value of internal subset DTD"));
        }

        void bombWF()
        {
            throwNotWellFormed(text("Invalid entity reference syntax",s));
        }


        while (!empty)
        {
            if (front == '%')
            {
                // must be part of entity definition
                popFront();
                expectEntityName(entityName_);
                // can get the entity referred to?
                if (dtd_.isInternal_)
                {
                    // but if we are processing a parameter entity that is external, the rule is relaxed
                    if (!srcExternalEntity)
                    {
                        if (!isPE)
                            bombWF_Internal("General entity");
                        else
                            bombWF_Internal("Parameter entity");
                    }
                }
                else
                {
                    EntityData eref = dtd_.paramEntityMap[entityName_.toArray];
                    if (eref is null)
                    {
                        bombWF();
                    }
                }
            }
            else if (front == '&')
            {
                popFront();
                if (empty)
                    bombWF();

                if (front == '#')
                {
                    uint radix = void;
                    expectedCharRef(radix);
                }
                else
                {
                    if (!getXmlName(entityName_) || empty || front != ';')
                        bombWF();
                    popFront();
                }
            }
            else
                popFront();
        }
    }


    /// get the NDATA name
    bool parseNData(ref string opt)
    {
        //ParseInput src = ctx_.in_;

        munchSpace();
        if (matchInput("NDATA"))
        {
            // reference to a notation which must be
            // declared (? in advance)
            int spacect = munchSpace();
            if (!getXmlName(entityName_))
            {
                throwNotWellFormed("No NDATA name");
            }
            if (spacect == 0)
            {
                throwNotWellFormed("need space before NDATA name");
            }
            opt = entityName_.idup;
            return true;
        }
        return false; // no such thing
    }
    /// process the ENTITY declaration
    void parseEntity()
    {
        int spacect1 = munchSpace(); // after keyword
        dchar test;


        bool isPE = matchInput('%');

        int spacect2 = munchSpace();

        if ((spacect1==0) || (isPE && (spacect2==0)))
            throwNotWellFormed("missing space in Entity definition");


        EntityData contextEntity = (isPE ? entityContext() : null);

        if (!getXmlName(entityName_))
        {
            throwNotWellFormed("Entity must have a name");
        }
         string ename = entityName_.idup;
        spacect2 = munchSpace();
        if (namespaceAware_ && (ename.indexOf(':') >= 0))
        {
            throwNotWellFormed(text("Entity Name must not contain a ':' in namespace aware parse ", ename));
        }

        string sys_ref;
        string public_ref;
        string ndata_ref;

        EntityData edef = dtd_.getEntity( ename, isPE);

        if (isStandalone_ && isPE)
            dtd_.undeclaredInvalid_ = true;

        EntityType etype = isPE ? EntityType.Parameter : EntityType.General;
        if (edef is null)
        {
            edef = new EntityData(ename, etype);
            edef.isInternal_ = dtd_.isInternal_;
            edef.context_ = contextEntity;

            if (isPE)
                dtd_.paramEntityMap[ename] = edef;
            else
                dtd_.generalEntityMap[ename] = edef;
        }
        else
        {
            // Done this one before. Parse, but do not overwrite the first encountered version.
            edef = new EntityData(ename, etype);
            // created, check, but afterwards forget it
        }

        ExternalID extID;

        if (getExternalUri(extID))
        {

            if (extID.systemId_ is null)
                throwNotWellFormed("Entity ExternalID PUBLIC needs SystemLiteral");
            edef.src_ = extID;
            /*if ((entityDir !is null) && !isabs(extID.systemId_))
            {
            	edef.src_.systemId_ = std.path.join(entityDir, extID.systemId_);
            }
            */

            spacect1 = munchSpace();
            string ndata_name;

            if (parseNData(ndata_name))
            {
                if (ndata_name.length > 0)
                {
                    if (spacect1 == 0)
                        throwNotWellFormed("Space needed before NDATA");

                    if (isPE)
                        throwNotWellFormed("NDATA cannot be in Parameter entity");
                    /*
                    /// lookup is only
                    auto pnote = ndata_name in dtd_.NotationMap;
                    Notation note = (pnote !is null) ? *pnote : null;
                    if (note is null)
                    	throwNotWellFormed(text("No notation named ", ndata_name));
                    */

                    edef.ndataref_ = ndata_name;


                }
            }
        }
        else
        {
            Array!char estr;

            if (spacect2 == 0)
            {
                throwNotWellFormed("space needed before value");
            }
            if (!unquoteValue(estr))
            {
                throwNotWellFormed("No entity value found");
            }

            if (estr.length > 0)
            {
                if (startsWith(estr.toArray,"<?xml"))
                {
                    throwNotWellFormed("internal entity cannot start with declaration");
                }
                string eval = estr.idup;
                verifyEntitySyntax(eval, isPE);
                edef.value_ = eval;
                edef.status_ = EntityData.Found;
                edef.reftype_ = RefTagType.ENTITY_REF;
            }
            else
            {
                // are empty ENTITY legal?
                edef.value_ = null;

            }
            if (edef.value_.length == 0)
            {
                edef.status_ = EntityData.Expanded;
                // its also ready to register
                /*Entity xe = new Entity(edef);
                DocumentType doct = dtd_.docTypeNode_;

                NamedNodeMap map = doct.getEntities();
                map.setNamedItem(xe);*/
            }
        }

        munchSpace();
        if (empty || front != '>')
        {
            throwErrorCode(ParseErrorCode.MISSING_END_BRACKET);
        }
        markupDepth_--;
        popFront();
    }
    /// Some element attribute value is used as unique id
    void registerId(string elemId, string attName)
    {
        dtd_.elementIDMap[elemId] = attName;
    }
    /// No end to attribute list functions
    uint checkAttributeValueDef(string value)
    {
        // check that any entity definitions are already defined
        // at this point in the DTD parse but do not process fully.

        auto pp = contextPopper(this,value);

        uint NameExpected()
        {
            return estk_.pushMsg(getErrorCodeMsg(ParseErrorCode.BAD_ENTITY_REFERENCE),ParseError.fatal);
        }

        while(!empty)
        {
            if (front == '&')
            {
                popFront();
                if (empty)
                    return NameExpected();
                if (front == '#')
                {
                    // TODO: get valid character reference, or leave it?

                }
                else
                {

                    if (!getXmlName(entityName_))
                    {
                        return NameExpected();
                    }
                    auto refName = entityName_.toArray;
                    auto pc = refName in charEntity_;
                    if (pc is null)
                    {
                        EntityData edef = dtd_.getEntity(refName);
                        if (edef is null)
                        {
                            string msg = text("Entity not defined in attribute definition ", refName);

                            if (!isStandalone_)
                                throwParseError(msg);
                            else
                                throwNotWellFormed(msg);
                        }
                        // if notation, not a parsed entity
                        if (edef.ndataref_.length > 0)
                        {
                            throwNotWellFormed( text("Cannot use notation entity as value: ", refName));
                        }

                        if (edef.src_.systemId_.length > 0)
                        {
                            throwNotWellFormed( text("Cannot use external entity as value: ", refName));
                        }
                    }
                }
            }
            else
                popFront();
        }
        return true;
    }
    /// add default value to attribute definition
    uint addDefaultValue(AttributeDef attDef)
    {
        //ParseInput src = ctx.in_;
        Array!char	attValue;

        if (unquoteValue(attValue) && (attValue.length > 0))
        {
            string check = attValue.idup;
            if (!checkAttributeValueDef(check))
            {
                throwNotWellFormed("attribute value check failed");
            }

            switch(attDef.dataform)
            {
            case AttributeType.att_id:
                if (validate_)
                    estk_.pushMsg(text("ID attribute must not have a default value: ",attDef.id),ParseError.invalid);
                break;
            case AttributeType.att_nmtoken:
                if (validate_)
                {
                    if (!isNmTokenImpl(check))
                        estk_.pushMsg(text("default value should be NMTOKEN: ",attDef.id),ParseError.invalid);
                }
                break;
            default:
                break;
            }


            if (attDef.values.length == 0)
            {
                attDef.values ~= check;
                attDef.defaultIndex = 0;
            }
            else
            {
                bool att_exists = false;
                foreach(ix, s ; attDef.values)
                {
                    if (s == check)
                    {
                        attDef.defaultIndex = cast(int)ix;
                        att_exists = true;
                        break;
                    }
                }
                if (validate_ && !att_exists)
                {
                    estk_.pushMsg(("default value should be in list"),ParseError.invalid);
                }
            }
            return true;
        }
        throwNotWellFormed("default attribute empty");
        assert(0);
    }
    /// More for the ATTLIST
    private bool getAttributeDefault(ref AttributeDefault dft)
    {
        string dfkey;
        if (!getUpperCaseName(dfkey))
        {
            throwNotWellFormed( "need attribute #[default]");
        }
        if (dfkey == "REQUIRED")
            dft = AttributeDefault.df_required;
        else if (dfkey == "IMPLIED")
            dft = AttributeDefault.df_implied;
        else if (dfkey == "FIXED")
            dft = AttributeDefault.df_fixed;
        else
            throwNotWellFormed( text("Unknown attribute specification ",dfkey));

        return true;
    }

    /// More for the ATTLIST
    bool collectAttributeEnum( AttributeDef adef, bool isNotation)
    {
        // call after getting a '('
        bool gotName;
        string attValue;

        while (!empty)
        {
            munchSpace();
            gotName = isNotation ? getXmlName(scratch_) : getXmlNmToken(scratch_);
            if (!gotName)
            {
                throwNotWellFormed("attribute enumeration");
            }
            attValue = scratch_.unique();
            adef.values ~= attValue;

            munchSpace();
            if (empty)
                break;
            if (front == ')')
            {
                parenDepth_--;
                popFront();
                return true;
            }
            else if (front != '|')
            {
                throwNotWellFormed(" expect | in value list");
            }
            else
                popFront();
        }
        return false;
    }
    /// if a parsed entity reference encountered push it to the front of stream
    private bool peCheck(dchar sep = 0x00, bool allowed = true)
    {
        if (empty)
            return false;
        if (front != '%')
            return true;
        popFront();

        expectEntityName(entityName_);

        if (!allowed)
        {
            // get the entity name and say its not allowed here
            throwNotWellFormed("parameter entity not allowed in internal subset");
        }

        StringSet  eset;
        auto peName = entityName_.toArray;

        EntityData ed = getParameterEntity(peName,eset, true);
        if (ed is null)
        {
            throwNotWellFormed(text("Unabled to fetch entity ",peName));
        }

        string content = ed.value_;
        if (content.length > 0)
        {
            if (sep)
                pushFront(sep); // to come after
            doPushContext(content, false, ed);
            if (sep)
                pushFront(sep); // to come before

            // new context, decode content

        }
        return true;
    }

    /// ATTLIST .  This function is far too big
    int parseAttList()
    {
        //bool validate = true; //ctx_.validate;
        //ParseInput src = ctx.in_;
        int spacect =  munchSpace();
        if (front == '%')
        {
            if (!peCheck(0x20,!dtd_.isInternal_))
                return false;
            spacect = munchSpace();
        }

        if (!getXmlName(entityName_))
        {
            throwNotWellFormed("Element name required for ATTLIST");
        }
        if (spacect == 0)
            throwNotWellFormed("need space before element name");
        munchSpace();
        // nice to know that element exists
        string ename = entityName_.idup;
        AttributeList def = dtd_.getAttributeList(ename);

        if (def is null)
        {

            def = new AttributeList(ename);
            //def.peRef_ = this.peReference_;
            dtd_.addAttributeList(def);
        }

        def.isInternal_ = dtd_.isInternal_;
        // TODO : maybe replace with AttributeDef.isInternal


        ElementDef edef = dtd_.getElementDef(ename);

        if (edef !is null)
        {
            edef.attributes = def;
        }
        int ct = 0; // count the number of names
        while (true)
        {
            // get the name of the attribute

            string attType;

            munchSpace();

            if (!peCheck(0,!dtd_.isInternal_) && (ct == 0))
            {
                throwNotWellFormed("incomplete ATTLIST");
            }

            if (!empty && front=='>')
            {
                markupDepth_--;
                popFront();
                break;
            }

            if (!getXmlName(entityName_))
            {
                throwNotWellFormed("Expected attribute name");
            }
            ct++;

            AttributeDef adef = new AttributeDef(entityName_.idup);

            adef.isInternal = dtd_.isInternal_;
            if (!munchSpace())
                return false;

            if (matchInput("NOTATION"d))
            {
                adef.dataform = AttributeType.att_notation;
                if (!munchSpace())
                    return false;

                if (!matchParen('(') || !collectAttributeEnum(adef, true))
                {
                    throwNotWellFormed("format of attribute notation");
                }

                int spct = munchSpace();

                if (matchInput('#'))
                {
                    if (!getAttributeDefault(adef.require))
                        return false;
                    spct = munchSpace();
                }

                if (empty)
                    break;
                if (front == '\'' || front == '\"')
                {
                    if (!spct)
                        throwNotWellFormed("space before value");
                    if (!addDefaultValue(adef))
                        return false;
                }
            }
            // get the type of the attribute
            else if (matchParen('('))
            {
                adef.dataform = AttributeType.att_enumeration;
                if (!collectAttributeEnum(adef, false))
                {
                    throwNotWellFormed("format of attribute enumeration");
                }
                int spaceCt = munchSpace();

                if (matchInput('#'))
                {
                    if (!spaceCt)
                        throwNotWellFormed("Space missing");

                    if (!getAttributeDefault(adef.require))
                        return false;
                    if (adef.require == AttributeDefault.df_fixed)
                    {
                        if (! munchSpace())
                            return false;
                        if (!addDefaultValue(adef))
                            return false;
                        spaceCt =  munchSpace();
                        /*if (!unquoteValue(dfkey))
                        {
                        	return push_error("fixed value expected");
                        }
                        adef.values ~= toUTF8(dfkey);
                        adef.defaultIndex = adef.values.length - 1;*/
                    }
                }

                if (front == '\'' || front == '\"')
                {
                    if (!spaceCt)
                        throwNotWellFormed("space before value");
                    if (!addDefaultValue(adef))
                        return false;
                }
            }
            else
            {
                // expecting a special name
                string  tname;
                if (!getUpperCaseName(tname))
                {
                    throwNotWellFormed("Expected attribute type in ATTLIST");
                }

                AttributeType*  patte = tname in AttributeDef.stdAttTypeList;

                if (patte is null)
                {
                    throwNotWellFormed(text("Unknown attribute type in ATTLIST ",tname));
                }
                adef.dataform = *patte;

                if (adef.dataform == AttributeType.att_id)
                {
                    // only allowed on id attribute
                    if (def.idDef !is null)
                    {
                        if (validate_)
                            estk_.pushMsg(text("Duplicate ID in ATTLIST: ",def.idDef.id),ParseError.invalid);
                    }
                    else
                    {
                        def.idDef = adef;
                        if (validate_)
                            registerId(def.id, adef.id);
                    }
                }
                // followed by maybe a default indication or list of names


                if (!peCheck(0x20,!dtd_.isInternal_))
                    return false;

                if (!munchSpace())
                    return false;


                bool enddef = false;

                while (!enddef)
                {
                    if (empty || matchMarkup('>'))
                    {
                        throwNotWellFormed("unfinished attribute definition");
                    }
                    if (!peCheck(0x20,!dtd_.isInternal_))
                        return false;

                    munchSpace();

                    if (empty)
                        ThrowEmpty();

                    if (front == '#')
                    {
                        popFront();
                        enddef = true;
                        if (!getAttributeDefault(adef.require))
                            return false;
                        if (adef.require == AttributeDefault.df_fixed)
                        {
                            // error if this ID
                            if (!munchSpace())
                            {
                                throwNotWellFormed("space required before value");
                            }

                            Array!char dfkey;
                            if (!unquoteValue(dfkey))
                            {
                                throwNotWellFormed("fixed value expected");
                            }
                            adef.values ~= dfkey.idup;
                            adef.defaultIndex = cast(int) adef.values.length - 1;
                        }
                    }
                    else if ((front=='\'')||(front=='\"'))
                    {
                        if (!addDefaultValue(adef))
                            throwNotWellFormed("Parse value failed");
                        enddef = true;
                    }
                    else
                    {
                        throwNotWellFormed(text("Unknown syntax in ATTLIST ",adef.id));
                    }
                    if (validate_ && (adef.dataform == AttributeType.att_id))
                    {
                        if ( (adef.require != AttributeDefault.df_required)
                                && (adef.require != AttributeDefault.df_implied))
                            estk_.pushMsg(text("Default must be #REQUIRED or #IMPLIED for ",adef.id),ParseError.invalid);
                    }

                }
            }
            AttributeDef existing = def.attributes_.get(adef.id, null);
            if (existing is null)
            {
                def.attributes_[adef.id] = adef;
                adef.attList = def;
            }

        }
        return true;
    }
    /// adjust for getting a <!
    final bool isOpenBang()
    {
        if (!empty && front == '<')
        {
            markupDepth_++;
            popFront();
            if (!empty && front == '!')
            {
                popFront();
                return true;
            }
            markupDepth_--;
            pushFront('<');
        }
        return false;
    }
    /// Count for starting <![
    final bool isSquaredStart(int extra = 1)
    {
        if (!isOpenBang())
            return false;
        if (empty || front != '[')
        {
            // undo
            markupDepth_--;
            pushFront('!');
            pushFront('<');
            return false;
        }
        popFront();
        squareDepth_ += extra;
        return true;
    }

    /// adjust counts for ]]>
    final bool isSquaredEnd()
    {
        if (!empty && front == ']')
        {
            squareDepth_--;
            popFront();
            if (!empty && front == ']')
            {
                squareDepth_--;
                popFront();
                if (!empty && front == '>')
                {
                    markupDepth_--;
                    popFront();
                    return true;
                }
                if (!empty)
                {
                    squareDepth_ += 2;
                    pushFront("]]");
                    return false;
                }

                throwNotWellFormed("Expected ']]>'");
            }
            else
            {
                squareDepth_++;
                pushFront(']');
                return false;
            }
        }
        return false;
    }

    /** skip through the text after IGNORE, until it ends.
    	Check only other conditional starts and ends and CDATA
    	and entity which might be these */

    private void ignoreDocType()
    {
        dchar[] dfkey;

        while (!empty)
        {
            switch(front)
            {
            case '<':
                if (isSquaredStart(2)) // because of ]] at end
                {
                    ignoreDocType();
                }
                else
                    popFront();
                break;
            case ']':
                if (isSquaredEnd())
                    return;
                popFront();
                break;
            default:
                popFront();
                break;
            }
        }
        //throwNotWellFormed("imbalanced []");
    }

    /// read content of file specified by SYSTEM id, also return directory of path
    bool getSystemEntity(string sysid, ref string opt, ref string baseDir)
    {
        //IXMLParser vp, Document doc, string sysid, ref string opt, ref string baseDir
        return .getSystemEntity(this,sysid,opt, baseDir );
    }

    /// Recursive lookup for %PENAME, eliminate circular references, by storing names in the set

    EntityData getParameterEntity(const(char)[] lookupName, ref StringSet stk, bool isValue = true)
    {
        EntityData pe = dtd_.getEntity(lookupName,true);

        if (pe is null)
        {
            return null;
        }
		string peName = lookupName.idup;
        if (pe.status_ < EntityData.Expanded)
        {
            if (!stk.put(peName))
            {
                estk_.pushMsg(text("Recursion for entity: ",peName),ParseError.error);
                return null;
            }
            if (pe.status_ == EntityData.Unknown)
            {
                auto sys_uri = pe.src_.systemId_;

                if ((sys_uri is null) || (sys_uri.length == 0))
                {
                    estk_.pushMsg("no system reference for entity",ParseError.fatal);
                    return null;
                }

                string srcput;
                string baseDir;

                if (pe.context_ !is null)
                {
                    sys_uri = std.path.buildPath(pe.context_.baseDir_, sys_uri);
                }
                if (!getSystemEntity(sys_uri, srcput, baseDir))
                {
                    estk_.pushMsg("resolve system reference failure", ParseError.fatal);
                    return null;
                }
                pe.isInternal_ = false;
                pe.baseDir_ = baseDir;
                pe.value_ = srcput;
                pe.status_ = EntityData.Found;
            }
            if (pe.value_.length > 0)
            {
                string nopt;
                {
                    auto pp = contextPopper(this, pe.value_);
                    if (!textReplaceCharRef(nopt))
                    {
                        estk_.pushMsg("bad char references",ParseError.fatal);
                        return null;
                    }
                }
                if (isValue)
                {
                    string replaced;

                    if (!textReplaceEntities(pe.isInternal_, nopt, replaced,stk))
                    {
                        estk_.pushMsg("entity replacement failed",ParseError.fatal);
                        return null;
                    }
                    nopt = replaced;
                }
                pe.value_ = nopt;
            }
            else
            {
                pe.value_ = null;
            }
            pe.status_ = EntityData.Expanded;
            stk.remove(peName);
        }
        return pe;
    }
    /// got a %, so parse the name and fetch the EntityData
    EntityData fetchEntity(ref string peName, bool isValue)
    {
        expectEntityName(entityName_);

        StringSet eset;
        EntityData ed = getParameterEntity(entityName_.toArray, eset, isValue);

        if (ed is null)
        {
            throwParseError(text("Unabled to fetch entity ",peName));

            //return ctx_.push_error(text("Unabled to fetch entity ",peName));
        }
        return ed;
    }
    /// encounter entity reference, so start a new context
    bool pushEntityContext(bool isValue = true)
    {
        string peName;
        EntityData ed = fetchEntity(peName,isValue);
        if (ed is null)
        {
            return false;
        }
        string content = ed.value_;
        if (content.length > 0)
        {
            doPushContext(content,false,ed);
        }
        return true;
    }
    static const string  kIncludeIgnoreMsg = "INCLUDE or IGNORE expected";

    /// Convoluted DOCTYPE syntax
    void parseDtdInclude()
    {
        munchSpace();
        if (matchInput('%'))
        {
            pushEntityContext();
            munchSpace();
        }
        string nameMatch;

        if (!getUpperCaseName(nameMatch))
        {
            throwNotWellFormed(kIncludeIgnoreMsg);
        }

        munchSpace();
        if (!isOpenSquare())
        {
            throwNotWellFormed("expected '['");
        }
		bool isInternalContext =  (entity_ is null || entity_.isInternal_);

        if (nameMatch == "INCLUDE")
        {
            if (dtd_.isInternal_ && isInternalContext)
                throwNotWellFormed("INCLUDE is not allowed in internal subset");
            munchSpace();
            constructDocType(DocEndType.doubleDocEnd);
        }
        else if (nameMatch == "IGNORE")
        {
            if (dtd_.isInternal_ && isInternalContext)
                throwNotWellFormed("IGNORE is not allowed in internal subset");
            munchSpace();
            ignoreDocType();
        }
        else
        {
            throwNotWellFormed(kIncludeIgnoreMsg);
        }
    }
    void constructDocType(DocEndType docEnd)
    {
        pumpStart();

        while(!empty)
        {
            // before checking anything, see if character reference need decoding
            if (front == '&')
            {
                uint radix = void;
                front = expectedCharRef(radix);
            }

            munchSpace();

            final switch(docEnd)
            {
            case DocEndType.noDocEnd:
                if (empty)
                    return;
                break;
            case DocEndType.singleDocEnd:
                if (isCloseSquare())
                    return;
                break;
            case DocEndType.doubleDocEnd:
                if (isSquaredEnd())
                    return;
                break;
            }

            if (isOpenBang())
            {
                itemCount++;
                if (isOpenSquare())
                {
                    parseDtdInclude();
                    continue;
                }

                if (matchInput("--"d))
                {

                    parseComment(scratch_);
                    // TODO: stick comment somewhere ?, child of DocumentType?
                }
                else if (matchInput("ATTLIST"d))
                {
                    parseAttList();
                }
                else if (matchInput("ENTITY"d))
                {
                    parseEntity();
                }
                else if (matchInput("ELEMENT"d))
                {
                    parseDtdElement();
                }
                else if (matchInput("NOTATION"d))
                {
                    parseDtdNotation();
                }
                else
                {
                    throwNotWellFormed("DTD unknown declaration ");
                }
                checkErrorStatus();
            } // not a <! thing
            else if (matchInput('%'))
            {
                if (!pushEntityContext(false))
                    if (!dtd_.isInternal_)
                        throwParseError("Undefined parameter entity in external entity");
            }
            else if (isPIStart())
            {
                XmlReturn iret;
                doProcessingInstruction(iret);
                handleProcessInstruction(iret);// do something
                itemCount++;
            }
            else if (empty)
            {
                break;
            }
            else
            {
                // no valid match
                if ((docEnd == DocEndType.doubleDocEnd) && matchInput(']'))
                    throwNotWellFormed("Expected ]]>");
                throwNotWellFormed("DTD unknown declaration ");
            }
        }
    }
    bool getPublicLiteral(ref string opt)
    {
        Array!(char) app;

        if (!empty && (front == '\"' || front == '\''))
        {
            unquoteValue(app);
            if (app.length == 0)
            {
                opt = "";
                return true;
            }
        }
        else
            throwNotWellFormed("Quoted PUBLIC id expected");

        string test = app.idup;
        bool hasSpace = false;
        int  ct = 0;
        app.length = 0;


        foreach(dchar c  ; test)
        {
            switch(c)
            {
            case 0x20:
            case 0x0A:
            case 0x0D: //0xD already filtered ?
                hasSpace = true;
                break;
            default:
                if (!isPublicChar(c))
                {
                    string msg = format("Bad character %x in PUBLIC Id %s", c, test);
                    throwNotWellFormed(msg);
                }
                if (hasSpace)
                {
                    if (ct > 0)
                        app.put(' ');
                    hasSpace = false;
                }
                ct++;
                app.put(c);
                break;
            }
        }
        opt = app.idup;
        return true;
    }
    /** A system literal is almost anything URI
    but cannot contain a fragment start with '#' */

    bool getSystemLiteral(ref Array!char opt)
    {
        if (empty)
            doUnexpectedEnd();

        if ((front == '\"') || (front == '\''))
        {
            unquoteValue(opt);
            if (opt.length == 0)
            {
                return true;
            }
            //throwNotWellFormed("Empty SYSTEM value");
        }
        else
        {
            return false;
        }
        char[] value = opt.toArray;
        if (value.indexOf('#') >= 0)
            throwParseError("SYSTEM URI with fragment '#'");
        return true;
    }
    // Read the specification of external entity PUBLIC, SYSTEM or just SYSTEM
    bool getExternalUri(ref ExternalID ext)
    {
        ExternalID result;
        //bool    onError;
        int spacect;
        //ParseInput src = ctx_.in_;

        bool doSystem()
        {
            spacect = munchSpace();
            Array!char opt;

            if (getSystemLiteral(opt))
            {
                if (spacect == 0)
                {
                    throwNotWellFormed("Need space before SYSTEM uri");
                }
                if (opt.length == 0)
                    ext.systemId_ = "";
                else
                    ext.systemId_ = opt.idup;
                return true;
            }
            return false;

        }

        if (matchInput("PUBLIC"))
        {
            spacect = munchSpace();
            string publicRef;

            if (!getPublicLiteral(publicRef))
                throwNotWellFormed("Expected a PUBLIC name");

            if (spacect == 0)
                throwNotWellFormed("Need space before PUBLIC name");

            doSystem();

            ext.publicId_ = publicRef;

            return true;
        }
        else if (matchInput("SYSTEM"))
        {
            doSystem();
            return true;
            //if (!doSystem()) return false;
        }
        return false;
    }


    void readExternalDTD()
    {
        foreach( extref ; dtd_.srcList_)
        {
            if (!extref.resolved_)
            {
                extref.resolved_ = parseExternalDTD(extref);
            }
        }
    }
    // Convert a sequence of isspace characters to a single space


	/+
    bool addDefaultAttributes(Element elem, AttributeList alist)
    {
        string value;
        string* pvalue;

        auto estk = errorStack();
        bool doValidate = validate_;
        bool reportExternal = (doValidate && isStandalone_ && (!dtd_.isInternal_ || !alist.isInternal_));

        string getDefaultValue(AttributeDef adef)
        {
            if (reportExternal && (!adef.isInternal))
                estk.pushMsg(text("standalone yes but default specfied in external: ", adef.id),ParseError.invalid);
            return adef.values[adef.defaultIndex];
        }

        NamedNodeMap eAttrMap = elem.getAttributes();
        foreach(adef ; alist.attributes_)
        {
            value = elem.getAttribute(adef.id);

            switch (adef.require)
            {
            case AttributeDefault.df_fixed:
            {
                string fixed = adef.values[adef.defaultIndex];
                if (value is null)
                {
                    if (isStandalone_ && doValidate && !alist.isInternal_)
                        estk.pushMsg(text("standalone and value fixed in external dtd: ",fixed),ParseError.invalid);
                    elem.setAttribute(adef.id,fixed);
                }
                else
                {
                    if ((value != fixed) && doValidate)
                        estk.pushMsg(text("Attribute ", adef.id, " fixed value ", value),ParseError.invalid);
                }
            }
            break;
            case AttributeDefault.df_implied:
                break;
            case AttributeDefault.df_required:
                if (value is null)
                {
                    if (adef.defaultIndex >= 0)
                    {
                        elem.setAttribute(adef.id,getDefaultValue(adef));
                    }
                    else
                    {
                        estk.pushMsg(text("Element ", elem.getTagName()," requires attribute: ", adef.id),ParseError.invalid);
                    }
                }
                break;
            default:
                if ((adef.defaultIndex >= 0) && (value is null))
                {
                    elem.setAttribute(adef.id,getDefaultValue(adef));
                }
                break;

            }
        }
        return true;
    }

    void internalProcessInstruction(string target, string data)
    {
        if (inDTD())
        {
            ProcessingInstruction pn = doc_.createProcessingInstruction(target,data);
            doc_.appendChild(pn);
        }
    }+/
protected:
    /// Parser input has reached and matched <!DOCTYPE
    override bool doDocType(ref XmlReturn iret)
    {
        inDTD_ = true;

        bool hadDeclaration = hasDeclaration;
        hasDeclaration = true;

        int spacect = munchSpace();


        if (! getXmlName(entityName_) )
            throwNotWellFormed("DOCTYPE name expected");

        if (!spacect)
            throwNotWellFormed("Need space before DOCTYPE name");
        munchSpace();
        if (empty)
            doUnexpectedEnd();

        // bind all together
        string xmlName = entityName_.idup;
        dtd_ = new DTDValidate();
        dtd_.id_ = xmlName;
		// make it difficult for the GC
        //dtd_.docTypeNode_ = new DocumentType(xmlName);
		//dtd_.docTypeNode_.setDTD( dtd_ );
        for(;;)
        {
            munchSpace();
            if (matchMarkup('>'))
            {
                break;
            }
            ExternalID eid;
            if (getExternalUri(eid))
            {
                // This dtd_ is an external entity
                ExternalDTD extdtd = new ExternalDTD(eid); // shadow parsed version
                dtd_.srcList_ ~= extdtd;
                //return dtd_.docTypeNode_; // indicate intention?

                if (!hadDeclaration)
                {
                    isStandalone_ = false;
                }
                else
                {
                    // TODO: check valid declaration?
                }
                munchSpace();
            }
            else if (isOpenSquare())
            {
                //readExternalDTD();
                dtd_.isInternal_ = true;
                // internal subset


                constructDocType(DocEndType.singleDocEnd);
            }
            else
            {
                throwNotWellFormed("Unknown DTD data");
            }
        }
        /// read external stuff ?
        readExternalDTD();


        /// process external parsed entities

        verifyGEntity();
        EntityData[] peArray = dtd_.paramEntities();

        if (peArray.length > 0)
            foreach(pe ; peArray)
        {
            int eStatus = pe.status_;
            if ((eStatus ==  EntityData.Found) && (!isStandalone_ || pe.isInternal_))
            {
                StringSet eset;
                EntityData ed = getParameterEntity(pe.name_,eset,true);
                if (ed is null)
                {
                    throwNotWellFormed( text("Error in parameter entity: ",pe.name_));
                }
            }
        }
        iret.node = dtd_;
        iret.type = XmlResult.DOC_TYPE;
        inDTD_ = false;
        hasDeclaration = ( hadDeclaration || (dtd_ !is null));
        if (state_ == PState.P_PROLOG)
        {
            munchSpace();
        }
        return true;
    }


}

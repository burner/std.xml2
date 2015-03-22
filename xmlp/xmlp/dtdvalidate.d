/**

Classes that support XML validation by DTD.

Shared types for different variants of DOCTYPE parsing.

Authors: Michael Rynn
Licence: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)

*/

module xmlp.xmlp.dtdvalidate;

import xmlp.xmlp.dtdtype;
import xmlp.xmlp.parseitem;
//import std.xmlp.linkdom;
import xmlp.xmlp.subparse;
import xmlp.xmlp.error;
import alt.zstring;
import std.conv;
import std.string;
import std.array;
import xmlp.xmlp.charinput;
import xmlp.xmlp.xmlchar;
import xmlp.xmlp.entitydata;
import xmlp.xmlp.charinput;
import xmlp.xmlp.entity;
//import hash.arraymap;

import std.path, std.file, std.stream;

static if (__VERSION__ <= 2053)
{
    import  std.ctype.isspace;
    alias std.ctype.isspace	isWhite;
}
else
{
    import  std.ascii;
}



/// Data collected during parse of DOCTYPE
/// this might be called on demand to parse external entity?
class DTDValidate
{
    ExternalDTD[]	srcList_;
    string		id_;

    bool			isInternal_;
    bool			undeclaredInvalid_;	// undeclared entity references are invalid instead of not-wf? Errata 3e E13
    //DocumentType	docTypeNode_; // DOM interface

    EntityDataMap		paramEntityMap;
    EntityDataMap 		generalEntityMap;
    EntityDataMap		notationMap;

    ElementDef[string]		elementDefMap;
    AttributeList[string]	attributeListMap;

    StringMap					elementIDMap;


    EntityData[]   paramEntities()
    {
        return paramEntityMap.values;
    }

    void addElementDef(ElementDef def)
    {
        elementDefMap[def.id] = def;
    }
    ElementDef getElementDef(string id)
    {
        auto pdef = id in elementDefMap;
        return (pdef is null) ? null : *pdef;
    }

    AttributeList getAttributeList(const(char)[] id)
    {
        auto atlist = id in attributeListMap;
        return (atlist is null ? null : *atlist);
    }

    void addAttributeList(AttributeList atlist)
    {
        attributeListMap[atlist.id] = atlist;
    }
    /// Normalise a completed DTD AttributeList.
    private bool normaliseAttributeList(IXMLParser vp, AttributeList alist)
    {
        ErrorStack estk = vp.getErrorStack();

        bool doValidate = vp.validate();
        bool reportExternal = doValidate && vp.isStandalone();
        PackedArray!char	valueList;

        foreach(adef ; alist.attributes_)
        {
            string[] oldvalues = adef.values;
            if ((adef.dataform == AttributeType.att_idref)
                    ||(adef.dataform == AttributeType.att_idrefs)
                    ||(adef.dataform == AttributeType.att_id)
               )
            {
                if (doValidate && (vp.idSet() is null))
                    vp.createIdSet();
            }
            foreach(i, sv ; oldvalues)
            {
                bool reqExternal = false;
                string result;
                attributeNormalize(vp, adef, sv, result, adef.dataform, reqExternal);
                if (reportExternal && reqExternal)
                    estk.pushMsg(text("attribute requires external document for normalisation: ",adef.id),ParseError.invalid);
                valueList ~= result;
            }
            adef.values = valueList.idup();
        }
        if (estk.errorStatus > 0)
        {
            estk.pushMsg(text("Errors during ATTLIST normalisation for ",alist.id),ParseError.invalid);
            vp.reportInvalid();
        }
        return true;
    }


    /// Validate the Attributes. The parser interface is required somehow.
    void validateAttributes(IXMLParser cp, ref XmlReturn ret)
    {

        bool doValidate = cp.validate();

        // see that each attribute was declared
        AttributeDef atdef;
        AttributeList atlist;
        AttributeType	attype;
        ErrorStack estk = cp.getErrorStack();
        string aValue;
        string eName = ret.scratch;

        auto pdef = eName in elementDefMap; //
        
        if (pdef !is null)
        {
            auto edef = *pdef;
            atlist = edef.attributes;

            if (atlist !is null)
            {
                if (!atlist.isNormalised_)
                    normaliseAttributeList(cp,atlist);
                //vp.addDefaultAttributes(iret,atlist);
            }
            else if (doValidate && (ret.attr.length > 0))
            {
                estk.pushMsg(text("No attributes defined for element ",eName),ParseError.invalid);
                return;
            }
        }
		
		foreach(n,v ; ret.attr)
		{
			atdef = null;

			if (atlist !is null)
			{
				auto padef = n in atlist.attributes_;
				/// TODO : if not validating, treat not declared as CDATA
				if (padef is null)
				{
					if (doValidate)
						estk.pushMsg(text("Attribute not declared: ",n),ParseError.invalid);
				}
				else
				{
					atdef = *padef;
				}
			}

			attype = (atdef is null) ? AttributeType.att_cdata : atdef.dataform;
			bool reqExternal = false;
			attributeNormalize(cp, atdef, v, aValue, attype, reqExternal);
			if (v != aValue)
				ret.attr[n] = aValue;
		}

        if (atlist !is null)
            addDefaultAttributes(cp, ret ,atlist);
        if (doValidate)
        {
            if (estk.errorStatus != 0)
                cp.reportInvalid();
        }
    }

    /** Return the EntityData object
    	Params:
    		name
    		isPE -- Defined by % and used in DTD (true), or an XML entity (false)
    */
    EntityData getEntity(const(char)[] name, bool isPE = false)
    {
        auto pdef = isPE ? name in paramEntityMap : name in generalEntityMap;
        return (pdef is null) ? null : *pdef;
    }

    /** The entity name is external to the DTD document */
    bool isExternalEntity(const(char)[] name, bool isPE = false)
    {
        auto edef = getEntity(name,isPE);
        if (edef is null)
            return false;
        return (edef.baseDir_ !is null);
    }

    /**
    	Normalise the Attributes, using the DTD AttributeDef.

    	Because of the requirements of ID, and validation of XmlNames depending on XML version
    	forced to use the IXMLParser interface to update the ID values during parse.

    	TODO: remove need for IXMLParser argument?
    */
    void attributeNormalize(IXMLParser vp, AttributeDef adef, string src, ref string value, AttributeType useType, bool reqExternal)
    {
        string result = value;
        vp.attributeTextReplace(src, result, 0);
        string[] valueset;
        uint vct = 0;
        bool replace = false;
        bool doValidate = vp.validate();
        ErrorStack estk = vp.getErrorStack();

        auto oldLength = result.length; // check for trimming
        switch(useType)
        {

        case AttributeType.att_id:
            result = strip(result);
            if (doValidate)
            {
                if (!vp.isXmlName(result))
                    estk.pushMsg(text("ID value ", result," is not a proper XML name"),ParseError.invalid);
                string elemId = adef.attList.id;
                IDValidate idval = vp.idSet();
                if (idval is null)
                    vp.throwNotWellFormed("no validation of ID configured");
                bool isUnique = idval.mapElementID(elemId, result);
                if (!isUnique)
                {
                    string existingElementName = idval.idElements[result];
                    estk.pushMsg(text("non-unique ID value ", result," already in element ",existingElementName),ParseError.invalid);
                }
            }
            break;
        case AttributeType.att_notation:
            // make sure the notation exists, but only if an attribute list is referenced
            if (doValidate)
            {
                foreach(notate ; adef.values)
                {
                    auto pnote = notate in notationMap;
                    if (pnote is null)
                        estk.pushMsg(text("ATTLIST refers to undeclared notation ",notate),ParseError.invalid);
                }
            }
            break;
        case AttributeType.att_enumeration:
        {
            // value must be one of the listed values
            result = strip(result);
            if (doValidate)
            {
                bool isListed = false;
                foreach(v ; adef.values)
                {
                    if (result == v)
                    {
                        isListed = true;
                        break;
                    }
                }
                if ( !isListed)
                    estk.pushMsg(text("value ",value," not listed in ATTRLIST"),ParseError.invalid);
            }
        }
        break;

        case AttributeType.att_entity:
        case AttributeType.att_entities:
            if (normalizeSpace(result) && !adef.isInternal)
                reqExternal = true;
            result = stripLeft(result);
            if (doValidate)
            {
                valueset = split(result);
                vct = cast(uint) valueset.length;

                if ((useType == AttributeType.att_entity) && (vct != 1))
                {
                    estk.pushMsg(text("Value not a valid entity name: ",value),ParseError.invalid);
                    break;
                }

                foreach(dval ; valueset)
                {
                    if (!vp.isXmlName(dval))
                    {
                        estk.pushMsg(text("Value ",dval," not a valid entity name: "),ParseError.invalid);
                    }
                    else
                    {
                        auto nt = dval in generalEntityMap;
                        if ( nt is null)
                        {
                            estk.pushMsg(text("attribute ",adef.id,": value is not an ENTITY: ",dval),ParseError.invalid);
                        }
                        else
                        {
                            // should be an unparsed entity, ie have an ndata_ref
                            auto ent = *nt;
                            if (nt.ndataref_.length == 0)
                            {
                                estk.pushMsg(text("attribute ",adef.id,": value is not an NDATA ENTITY: ",dval),ParseError.invalid);
                            }
                        }
                    }
                }
                if (vct == 0)
                    estk.pushMsg(text("Should be at least one value in idref | idrefs"),ParseError.invalid);
            }
            break;

        case AttributeType.att_nmtoken:
        case AttributeType.att_nmtokens:

            if (normalizeSpace(result) && !adef.isInternal)
                reqExternal = true;
            result = stripLeft(result);
            if (!doValidate)
                break;

            valueset = split(result);
            vct = cast(uint) valueset.length;
            replace = false;

            if (useType == AttributeType.att_nmtoken)
            {
                if (vct > 1)
                    estk.pushMsg(text("Value not a single NMTOKEN name: ",result),ParseError.invalid);
            }
            foreach(dval ; valueset)
            {
                if (!vp.isNmToken(dval))
                {
                    estk.pushMsg(text("Value not a valid NMTOKEN: ",dval),ParseError.invalid);
                }
            }
            if (vct == 0)
                estk.pushMsg(text("Should be at least one value in idref | idrefs"),ParseError.invalid);
            break;
        case AttributeType.att_idref:
        case AttributeType.att_idrefs:
            result = stripLeft(result);
            if (normalizeSpace(result) && !adef.isInternal)
                reqExternal = true;
            if (doValidate)
            {
                IDValidate idval = vp.idSet();

                valueset = split(result);
                vct = cast(uint) valueset.length;

                if ((useType == AttributeType.att_idref)&&(vct != 1))
                {
                    estk.pushMsg(text("Value not a valid IDREF name: ",result),ParseError.invalid);
                }
                foreach(dval ; valueset)
                {
                    if (!vp.isXmlName(dval))
                    {
                        estk.pushMsg(text("Value not a valid reference: ",dval),ParseError.invalid);
                    }
                    else if (idval !is null)
                    {
                        idval.checkIDRef(dval);
                    }
                }
                if (vct == 0)
                    estk.pushMsg(text("Should be at least one value in idref | idrefs"),ParseError.invalid);
            }
            break;
        default:
            break;
        }
        if ((result.length != oldLength) && !adef.isInternal)
            reqExternal = true;
        value = result;
    }

    /**
    	Insert missing attributes which have a default value.
    */
    bool addDefaultAttributes(IXMLParser cp, ref XmlReturn ret, AttributeList alist)
    {
        string value;
        string* pvalue;

        auto estk = cp.getErrorStack();
        bool doValidate = cp.validate();
        bool reportInvalid = doValidate && cp.isStandalone();
        bool reportExternal = (reportInvalid && (!isInternal_ || !alist.isInternal_));

        string getDefaultValue(AttributeDef adef)
        {
            if (reportExternal && (!adef.isInternal))
                estk.pushMsg(text("standalone yes but default specfied in external: ", adef.id),ParseError.invalid);
            return adef.values[adef.defaultIndex];
        }

		//hash.arraymap.HashTable!(string,string)		attrMap;
		// As long as no removals, keys and values will have no holes.
		//attrMap.setKeyValues(ret.names, ret.values);
        foreach(adef ; alist.attributes_)
        {
            value = ret.attr.get(adef.id,null);
            switch (adef.require)
            {
            case AttributeDefault.df_fixed:
            {
                string fixed = adef.values[adef.defaultIndex];
                if (value is null)
                {
                    if (reportInvalid && !alist.isInternal_)
                        estk.pushMsg(text("standalone and value fixed in external dtd: ",fixed),ParseError.invalid);
					ret.attr[adef.id] = fixed;
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
						ret.attr[adef.id] = getDefaultValue(adef);
                    }
                    else
                    {
                        estk.pushMsg(text("Element ", ret.scratch," requires attribute: ", adef.id),ParseError.invalid);
                    }
                }
                break;
            default:
                if ((adef.defaultIndex >= 0) && (value is null))
                {
					ret.attr[adef.id] = getDefaultValue(adef);
                }
                break;
            }
        }
        return true;
    }

    private bool normalizeSpace(ref string value)
    {
        Array!char	app;
        app.reserve(value.length);
        int spaceCt = 0;
        // only care about space characters
        for (size_t ix = 0; ix < value.length; ix++)
        {
            char test = value[ix];
            if (isSpace(test))
            {
                spaceCt++;
            }
            else
            {
                if (spaceCt)
                {
                    app.put(' ');
                    spaceCt = 0;
                }
                app.put(test);
            }
        }

        char[] result = app.toArray;
        if (result != value)
        {
            value = app.unique;
            return true;
        }
        return false;
    }
    bool fetchEntityValue(IXMLParser cp, string ename, bool isAttribute, ref EntityData ed)
    {

        auto ge = getEntity(ename);
        //auto pge = ename in dtd_.generalEntityMap;
        if (ge is null)
        {
            if (undeclaredInvalid_ && !isAttribute)
            {
                if ( cp.validate() )
                {
                    cp.getErrorStack().pushMsg(text("referenced undeclared entity ", ename),ParseError.invalid);
                    cp.reportInvalid();
                }
                // create EntityReference and pass it upwards ?
                //value = text('&',ename,';');
                return false; // stop recursive lookup!
            }
            else
                cp.throwUnknownEntity(ename);
        }
        ed = ge;

        if (ge.status_ == EntityData.Expanded)
            return true;

        StringSet eset;

        int reftype = RefTagType.UNKNOWN_REF;
        string value;
        if (!lookupReference(cp, ge.name_, value, eset, reftype))
        {
            cp.throwNotWellFormed(text("Error in entity lookup: ", ge.name_));
        }
        if (reftype==RefTagType.NOTATION_REF)
        {
            cp.throwNotWellFormed(text("Reference to unparsed entity ",ename));
        }
        if(isAttribute && cp.isStandalone() && reftype==RefTagType.SYSTEM_REF)
            cp.throwNotWellFormed("External entity in attribute of standalone document");
        return true;
    }

    bool lookupReference(IXMLParser vp, string entityName, out string value, StringSet stk, out int reftype)
    {
        //DocumentType doct = docTypeNode_;
        //NamedNodeMap map = doct.getEntities();
        //Node n = map.getNamedItem(entityName);
		/*
        if (n !is null)
        {
            Entity xe = cast(Entity) n;
            reftype = (xe.getSystemId() is null) ?  RefTagType.ENTITY_REF :  RefTagType.SYSTEM_REF;
            value =  xe.getNodeValue();
            return true;
        }
		*/
        EntityData entity = getEntity(entityName);

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

        if (! deriveEntityContent(vp, entity, stk, reftype))
            return false;

        switch(reftype)
        {
        case RefTagType.SYSTEM_REF:
            entity.isInternal_ = false;
            break;
        case RefTagType.NOTATION_REF:
            if (vp.inGeneralEntity())
                vp.throwParseError(format("Referenced unparsed data in entity %s", vp.getEntityName()));

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
            vp.getErrorStack().pushMsg(text("Value cannot be determined for entity: ",entity.name_),ParseError.error);
            return false;
        }
    }
    /// Go through the stages of fetching and resolving entity content. May be recursive.
    private bool deriveEntityContent(IXMLParser vp, EntityData entity, StringSet stk, out int reftype)
    {

        bool assignEmpty()
        {
            entity.status_ = EntityData.Expanded;
            entity.value_ = null;
            return true;
        }

        auto estk = vp.getErrorStack();
        if (vp.isStandalone())
        {
            if (!entity.isInternal_) // w3c test sun  not-wf-sa03
            {
                estk.pushMsg("Standalone yes and referenced external entity",ParseError.error);
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
                //auto nmap = docTypeNode_.getNotations();
               // auto n = nmap.getNamedItem(entity.ndataref_);
				auto n = notationMap.get(entity.ndataref_,null);

                if (n is null)
                {
                    if (vp.validate())
                        estk.pushMsg(text("Notation not declared: ", entity.ndataref_),ParseError.invalid);
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
                string sys_uri = entity.src_.systemId_;
                if (sys_uri.length > 0) // and not resolved?
                {
                    string esys;
                    string baseDir;
                    //Document doc = new Document();

                    if (!.getSystemEntity(vp, sys_uri, esys, baseDir))
                    {
                        estk.pushMsg("DTD System Entity not found",ParseError.error);
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
                    estk.pushMsg("DTD SYSTEM uri missing",ParseError.error);
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
                estk.pushMsg(text("recursion in entity lookup for ", entity.name_),ParseError.error);
                return false;
            }
            string tempValue;
            if (entity.value_.length > 0)
            {
                {
                    auto pp = contextPopper(vp, entity.value_);
                    if (!vp.textReplaceCharRef(tempValue))
                        return false;
                }


                StringSet eset;

                if (vp.inDTD() && !vp.textReplaceEntities(entity.isInternal_, tempValue, tempValue, eset))
                {
                    estk.pushMsg("parsed entity replacement failed",ParseError.error);
                    return false;
                }

                auto pp = contextPopper(vp,tempValue);
                vp.entityContext(entity);
                if (!vp.expandEntityData(tempValue, stk, reftype))
                {
                    estk.pushMsg("ENTITY value has bad or circular Reference",ParseError.error);
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
   /// Recursive lookup for %PENAME, eliminate circular references, by storing names in the set

    EntityData getParameterEntity(IXMLParser vp, const(char)[] peName, ref StringSet stk, bool isValue = true)
    {
        EntityData pe = getEntity(peName,true);

        if (pe is null)
        {
            return null;
        }

        if (pe.status_ < EntityData.Expanded)
        {
            if (!stk.put(peName.idup))
            {
                vp.getErrorStack().pushMsg(text("Recursion for entity: ",peName),ParseError.error);
                return null;
            }
            if (pe.status_ == EntityData.Unknown)
            {
                string sys_uri = pe.src_.systemId_;

                if ((sys_uri is null) || (sys_uri.length == 0))
                {
                    vp.getErrorStack().pushMsg("no system reference for entity",ParseError.fatal);
                    return null;
                }

                string srcput;
                string baseDir;

                if (pe.context_ !is null)
                {
                    sys_uri = std.path.buildPath(pe.context_.baseDir_, sys_uri);
                }
                //Document doc = new Document();
                if (!.getSystemEntity(vp, sys_uri, srcput, baseDir))
                {
                    vp.getErrorStack().pushMsg("resolve system reference failure", ParseError.fatal);
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
                    auto pp = contextPopper(vp, pe.value_);
                    if (!vp.textReplaceCharRef(nopt))
                    {
                        vp.getErrorStack().pushMsg("bad char references",ParseError.fatal);
                        return null;
                    }
                }
                if (isValue)
                {
                    string replaced;

                    if (!vp.textReplaceEntities(pe.isInternal_, nopt, replaced,stk))
                    {
                        vp.getErrorStack().pushMsg("entity replacement failed",ParseError.fatal);
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

}



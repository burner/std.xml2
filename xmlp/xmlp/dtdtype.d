/**

Classes that support XML validation by DTD.

Shared types for different variants of DOCTYPE parsing.

Authors: Michael Rynn
Licence: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)

*/

module xmlp.xmlp.dtdtype;

import xmlp.xmlp.parseitem;
import xmlp.xmlp.subparse;
import xmlp.xmlp.error;
import alt.zstring;
import alt.zstring;
import std.conv;
import std.string;
import xmlp.xmlp.charinput;
import xmlp.xmlp.xmlchar;
import xmlp.xmlp.entitydata;

static if (__VERSION__ <= 2053)
{
    import  std.ctype.isspace;
    alias std.ctype.isspace	isWhite;
}
else
{
    import  std.ascii;
}

/** Uses an associative array to imitate a set */






/// Kind of default value for attributes
enum AttributeDefault
{
    df_none,
    df_implied,
    df_required,
    df_fixed
}

/** Distinguish various kinds of attribute data.
  The value att_enumeration means a choice of pre-defined values.
**/
enum AttributeType
{
    att_cdata,
    att_id,
    att_idref,
    att_idrefs,
    att_entity,
    att_entities,
    att_nmtoken,
    att_nmtokens,
    att_notation,
    att_enumeration
}


/**
 * As a member of an AttributeList, the AttributeDef holds data required for
 * validation purposes on a single attribute name.
**/
version(CustomAA)
{
    import alt.arraymap;

    alias HashSet!string    StringSet;
    alias HashTable!(string, AttributeType) AttributeTypeMap;
    alias HashTable!(string, AttributeDef) AttributeDefMap;
}
else {
    alias AttributeType[string] AttributeTypeMap;
    alias AttributeDef[string] AttributeDefMap;

    struct StringSet
    {
        bool[string]	map;

        bool put(const(char)[] name)
        {
            bool* value = name in map;
            if (value !is null)
                return false;
            map[name.idup] = true;
            return true;
        }
        void remove(const(char)[] name)
        {
			// cheat
            map.remove(cast(immutable(char)[]) name);
        }
        void clear()
        {
            string[] keys = map.keys();
            foreach(k ; keys)
                map.remove(k);
        }
    }
}

class AttributeDef
{
    /// The name
    string		 id;
    /// What the DTD says it is
    AttributeType    dataform;
    /// Essential?
    AttributeDefault require;

    /// index of default value in values
    int    defaultIndex;
    /// list of allowed values, for particular AttributeType.
    string[]     values;

    __gshared AttributeTypeMap    stdAttTypeList;

    __gshared static this()
{
    stdAttTypeList["CDATA"] = AttributeType.att_cdata;
    stdAttTypeList["ID"] = AttributeType.att_id;
    stdAttTypeList["IDREF"] = AttributeType.att_idref;
    stdAttTypeList["IDREFS"] = AttributeType.att_idrefs;
    stdAttTypeList["ENTITY"] = AttributeType.att_entity;
    stdAttTypeList["ENTITIES"] = AttributeType.att_entities;
    stdAttTypeList["NMTOKEN"] = AttributeType.att_nmtoken;
    stdAttTypeList["NMTOKENS"] = AttributeType.att_nmtokens;
    stdAttTypeList["NOTATION"] = AttributeType.att_notation;
}
/// lookup for AttributeType from name.
static bool getStdType(string name, ref AttributeType val)
{
    AttributeType* tt = name in stdAttTypeList;
    if (tt !is null)
    {
        val = *tt;
        return true;
    }
    return false;
}

package bool         normalised;
package bool		 isInternal;
package AttributeList   attList;

this(string name)
{
    id = name;
    defaultIndex = -1;
}
}


/**
 * Has an ssociative array of AttributeDef objects by name.
 * Holds all the DTD definitions of attributes for an element type.
 * The idDef member holds the AttributeDef of associated ID attribute,
 *  if one was declared. The external member is used for validation against
 * standalone declarations.
*/
class AttributeList
{
    string		 id;
    //string  desc_; // unparsed list

    AttributeDefMap         attributes_;
    AttributeDef            idDef;
    bool					isInternal_;
    bool					isNormalised_;	 // all the values have had one time normalisation processing
    this(string name)
    {
        id = name;
    }

}

/// Used to mark ELEMENT declaration lists
package enum ChildSelect
{
    sl_one,
    sl_choice,
    sl_sequence
}

/// Used to mark ELEMENT declaration lists and element names
package enum ChildOccurs
{
    oc_not_set = 0,
    oc_allow_zero = 1,
    oc_one = 2,
    oc_zeroOne = 3,
    oc_allow_many = 4, //
    oc_oneMany = 6, // !zero, + one + many
    oc_zeroMany = 7 // no restriction zero + one + many
}

/// A single element name in a declaration list
package class ChildId
{
    string	id;
    ChildOccurs occurs;

    this()
{
}

this(string et)
{
    id = et;
}


}

/**
Holds the Child elements, how many, what combinations,
as set by the ELEMENT definition in the DTD,
in a tree structure.

*/
package class ChildElemList : ChildId
{
    ChildElemList	parent;
    ChildOccurs		occurs;
    ChildSelect     select;
    ChildId[]		children;

    void append(ChildId ch)
    {
        children ~= ch;
    }

    @property auto length()
    {
        return children.length;
    }

    ChildId opIndex(size_t ix)
    {
        if (ix < children.length)
            return cast(ChildId) children[ix];
        else
            return null;
    }

    intptr_t firstIndexOf(string name)
    {
        for(uintptr_t i = 0; i < children.length; i++)
            if (children[i].id == name)
                return i;
        return -1;
    }

    void addChildList(ChildElemList ch)
    {
        append(ch);
        ch.parent = this;
    }
    bool hasChild(string name, bool recurse = true)
    {
        foreach(ce ; children)
        {
            if (ce.id !is null)
            {
                if (name == ce.id)
                    return true;
            }
            else if (recurse)
            {
                ChildElemList list = cast(ChildElemList) ce;
                if (list !is null)
                {
                    return list.hasChild(name);
                }
            }
        }
        return false;
    }
}

package enum FelType
{
    fel_listbegin,
    fel_listend,
    fel_element
}

package struct FelEntry
{
    FelType  fel;
    ChildId	 item;
}

/**
 * A declaration of possible arrangements of child elements
 * and possibly character data for an ELEMENT. The validation
 * code lives with the XML parser.
 **/

/** XML and DTDs have ID and IDREF attribute types
 *  To fully validate these, need to collect all the values
 * of each element with an ID.
 * ID is the attribute which is supposedly unique, and only declared ID attribute one per element type.
 *
 * The IDValidation maps all the id attribute names, and all the elements
 *  refered to by any ID key value.
 *
 *  At the end of the parse, all the values in idReferences must have a mapped value in idElements.
 *  Do not need to keep all the idReferences.
 *  Once a mapping in idElements exists, the idReferences can be thrown away since it they have been validated.
 *  At the end of the  document idReferences.length should be zero.
 **/
class IDValidate
{
    /// contains the name of the id attribute by element name (one ID per element type)

    //string[string] idNames;
    string[string] idElements;
    int[string]       idReferences;


    /// check uniqueness by returning false if ID value exists already
    /// delete existing references tally as these are validated
    /// etag is used to record the name of a clashing element
    bool mapElementID(string etag, string id)
    {
        auto idvalue = (id in idElements);
        if (idvalue !is null)
            return false;
        idElements[id] = etag;
        idReferences.remove(id);
        return true;
    }

    /// return true if the reference is not yet validated
    bool checkIDRef(string refvalue)
    {
        auto idvalue = (refvalue in idElements);
        if (idvalue is null)
        {
            // referenced element not encountered (yet)
            auto ct = (refvalue in idReferences);
            if (ct !is null)
                *ct += 1;
            else
                idReferences[refvalue] = 1;
            return false;
        }
        return true;
    }
}

/// The  ELEMENT Dtd definition
class ElementDef
{
    string id;
    //string   desc_;
    bool    hasPCData;
    bool    hasElements;
    bool    hasAny;
    bool    isInternal;

    package FelEntry[]		flatList;

    ChildElemList   list; // this may be chucked away
    AttributeList   attributes;

    this(string name)//, string desc
    {
        id = name;
        //desc_ = desc;
    }

    // this effectively simplifies some kinds of expressions
    package void appendFlatList(ChildElemList elist)
    {
        if (elist.children.length > 0)
        {
            if (elist.children.length == 1)
            {
                // single list or single item
                ChildId ch = elist.children[0];
                if (ch.id !is null)
                {
                    // fix ups.

                    elist.select = ChildSelect.sl_one; // in case reduced by removal #PCDATA choice

                    if ((ch.occurs==ChildOccurs.oc_one) && (elist.occurs != ChildOccurs.oc_one))
                    {
                        // swap the occurs from outside the list to inside
                        ch.occurs = elist.occurs;
                        elist.occurs = ChildOccurs.oc_one;
                    }
                    if ((elist.parent !is null) && (elist.occurs == ChildOccurs.oc_one))
                    {
                        flatList ~= FelEntry(FelType.fel_element, ch);
                    }
                    else
                    {
                        flatList ~= FelEntry(FelType.fel_listbegin, elist);
                        flatList ~= FelEntry(FelType.fel_element, ch);
                        flatList ~= FelEntry(FelType.fel_listend, elist);
                    }
                }
                else
                {
                    // list contains one list, so move it up to parent.
                    ChildElemList clist = cast(ChildElemList) ch;
                    if (clist.occurs==ChildOccurs.oc_one)
                    {
                        clist.occurs = elist.occurs;
                        elist.occurs = ChildOccurs.oc_one;
                        clist.parent = elist.parent;
                        appendFlatList(clist);
                    }
                    else
                        goto FULL_LIST;
                }
                return;
            }
// label for goto
FULL_LIST:
            flatList ~= FelEntry(FelType.fel_listbegin, elist);
            foreach(ce ; elist.children)
            {
                if (ce.id !is null)
                    flatList ~= FelEntry(FelType.fel_element, ce);
                else
                {
                    ChildElemList cc = cast(ChildElemList) ce;
                    cc.parent = elist;
                    appendFlatList(cc);
                }
            }
            flatList ~= FelEntry(FelType.fel_listend, elist);

        }
    }

    package void makeFlatList()
    {
        flatList.length = 0;
        if (list !is null)
            appendFlatList(list);
    }

    bool hasChild(string ename)
    {
        // search the tree to find a match
        if (hasAny)
            return true;
        if (list !is null)
        {
            if (flatList.length == 0)
                makeFlatList();
            foreach(s ; flatList)
            {
                if (s.fel == FelType.fel_element)
                {
                    if (s.item.id == ename)
                        return true;
                }
            }
            return false;
        }
        else
            return false;
    }

    bool isPCDataOnly()
    {
        return (!hasElements && hasPCData);
    }

    bool isEmpty()
    {
        return (!hasElements && !hasPCData);
    }
}



class ExternalDTD
{
    ExternalID src_;
    bool	   resolved_;

    this(ref ExternalID eid)
    {
        src_ = eid;
    }
}

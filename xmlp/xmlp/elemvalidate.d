module xmlp.xmlp.elemvalidate;

import xmlp.xmlp.linkdom, xmlp.xmlp.dtdvalidate, xmlp.xmlp.dtdtype, xmlp.xmlp.error;
import std.stdint, std.conv;
/** created to break module dependency between linkdom, dtdvalidate and dtdtype

@Author: Michael Rynn

*/


/** Generate a string representation of ElementDef child elements x

itemIX should be position of a fel_listbegin, if not go back
*/

private string toFelString(FelEntry[] list, intptr_t itemIX)
{
    char[] val;
    char   sep;
    FelType  lastItem;

    void printOccurs(ChildOccurs oc)
    {
        switch(oc)
        {
			case ChildOccurs.oc_zeroMany:
				val ~= '*';
				break;
			case ChildOccurs.oc_zeroOne:
				val ~= '?';
				break;
			case ChildOccurs.oc_oneMany:
				val ~= '+';
				break;
			case ChildOccurs.oc_one:
			default:
				break;
        }
    }
    auto limit = list.length;

    ChildElemList nlist, clist;
    int	  depth = 0;

    if (itemIX >= limit)
    {
        if (limit == 0)
            return "";
        else
            itemIX = 0;
    }
    FelEntry s = list[itemIX];
    while (s.fel != FelType.fel_listbegin)
    {
        itemIX--;
        s = list[itemIX];
    }
    lastItem = 	FelType.fel_listbegin;

    while(itemIX < limit)
    {
        s = list[itemIX++];
        switch(s.fel)
        {
			case FelType.fel_listbegin:
				val ~= '(';
				clist = cast(ChildElemList) s.item;
				depth++;
				sep = (clist.select == ChildSelect.sl_choice) ? '|' : ',';
				break;
			case FelType.fel_listend:
				val ~= ')';
				depth--;
				if (depth <= 0)
				{
					itemIX = cast(int) limit;
					break;
				}
				if (clist !is null)
				{
					printOccurs(clist.occurs);
					clist = (clist.parent !is null) ? cast(ChildElemList) clist.parent : null;
					if (clist !is null)
						sep = (clist.select == ChildSelect.sl_choice) ? '|' : ',';
				}
				break;
			case FelType.fel_element:
				if (lastItem != FelType.fel_listbegin)
					val ~= sep;
				ChildId child = cast(ChildId) s.item;
				val ~= child.id;
				printOccurs(child.occurs);
				break;
			default:
				break;
        }
        lastItem = s.fel;
    }
    version(D_Version2)
    {
        return val.idup;
    }
    else
    {
        return val;
    }
}

private struct clistinfo
{
    ChildElemList  clist;
    bool	   	   match;
    intptr_t	   pIndex;
    intptr_t	   eIndex;

    void init(ChildElemList c, bool m, intptr_t fix, intptr_t eix)
    {
        clist = c;
        match = m;
        pIndex = fix;
        eIndex = eix;
    }
}

/// Given the ElementDef, check Element has conforming children
static bool validElementContent(ElementDef edef, Element parent, ErrorStack estk)
{
    // collect the children in temporary
    Node nd1 = parent.getFirstChild();
    Node[] seq  = (nd1 !is null) ? ChildNode.getNodeList(cast(ChildNode)nd1) : [];

    if (edef.flatList.length == 0)
    {
        edef.makeFlatList();
        if (edef.flatList.length == 0)
        {
            return true; // only concerned about missing elements
        }
    }
    // go through the flatlist, and ensure any mandatory elements
    // are present
    intptr_t elemIX = 0;
    intptr_t startElemIX = 0;

    auto limit = seq.length;
    ChildId ce;
    intptr_t itemIX = 0;
    bool needAnotherChoice = false;

    clistinfo[]  estack;
    ChildElemList clist;
    Element child;

    bool badSequence()
    {
        estk.pushMsg(text("Missing element choice of ",toFelString(edef.flatList,itemIX)));
        return false;
    }

    bool hasAnotherChoice()
    {
        // muast be do or die call
        // tried sequence is invalid, so is it part of another choice in the stack?
        // if so we need to take the elements consumed back for the alternate
        // and pop stack properly
        intptr_t failtop = estack.length-1;
        intptr_t top = failtop - 1;
        intptr_t endIX = itemIX - 1;  // start on the current FelEntry
        FelEntry[]	 list = edef.flatList;

        while (top >= 0)
        {
            // failtop has a parent, so go to end of failtop, and see if
            // there is another choice
            while (endIX < list.length)
            {
                if (list[endIX].fel == FelType.fel_listend)
                {
                    break;
                }
                endIX++;
            }
            // could assert here that the clist of listend is failtop

            if (endIX >= list.length)
                return false;

            if (estack[top].clist.select == ChildSelect.sl_choice)
            {
                // move along to next choice by moving past listend
                elemIX = estack[failtop].eIndex;
                itemIX = endIX + 1;
                estack.length = top+1;
                return true;
            }
            else
            {
                endIX++; // move into next territory
            }
            failtop -= 1;
            top -= 1;
        }
        return false;
    }


    Element nextElement()
    {
        while(elemIX < limit)
        {
            Element result = cast(Element)seq[elemIX];
            if (result !is null)
                return result;
            elemIX++;
        }
        return null;
    }

    bool isNextElementMatch(string id)
    {
        child = nextElement();
        return (child !is null) && (child.getTagName()==id);
    }
    void consumeId(string id)
    {
        Element ch = nextElement();
        while (ch !is null)
        {
            if (ch.getTagName() == id)
                elemIX++;
            else
                break;
            ch = nextElement();
        }
    }


    clistinfo* stacktop;

    while (itemIX < edef.flatList.length)
    {
        FelEntry s = edef.flatList[itemIX++];

        switch(s.fel)
        {
			case FelType.fel_listbegin:
				clist = cast(ChildElemList) s.item;
				// stack top will point to first item after list begin
				estack.length = estack.length + 1;
				estack[$-1].init(clist,false, itemIX, elemIX);
				break;
			case FelType.fel_listend:
				bool noPop = false;
				if (estack.length > 0)
				{
					stacktop = &estack[$-1];
					if (clist.select == ChildSelect.sl_choice)
					{
						if (!stacktop.match && ((clist.occurs & ChildOccurs.oc_one) > 0))
						{
							if (!hasAnotherChoice())
							{
								if ((clist.occurs & ChildOccurs.oc_allow_zero)==0)
									return badSequence();
								else
								{
									stacktop.match = true;
								}
							}
							break;
						}

					}
					else
					{
						// if we got here, presume that a sequence matched
						stacktop.match = true;
					}
					if ((nextElement() !is null) && ((clist.occurs & ChildOccurs.oc_allow_many) > 0) && (elemIX > startElemIX))
					{
						// made progress, so run again to see if it matches again

						itemIX = stacktop.pIndex;
						startElemIX = elemIX;
						stacktop.match = false;
						noPop = true;
					}

					if (!noPop)
					{
						// presumably this list was satisfied here?
						// if it was a member of parent list choice, need to inform that
						auto  slen = estack.length-1;
						bool wasMatch = estack[slen].match;
						estack.length = slen;

						if (slen > 0)
						{
							slen--;
							clist = estack[slen].clist;
							if (clist.select == ChildSelect.sl_choice)
								estack[slen].match = wasMatch;
						}

					}
				}
				break;
			case FelType.fel_element:
				ce = cast(ChildId) s.item;
				stacktop = &estack[$-1];
				if (clist.select == ChildSelect.sl_choice)
				{

					if (!stacktop.match)
					{
						if (isNextElementMatch(ce.id))
						{
							stacktop.match = true;
							elemIX++;
						}
					}
				}
				else
				{
					if ((clist.occurs & ChildOccurs.oc_one) > 0
                        &&(ce.occurs & ChildOccurs.oc_one) > 0)
					{
						// sequence must match
						if (!isNextElementMatch(ce.id))
						{
							if ((ce.occurs & ChildOccurs.oc_allow_zero)==0)
							{
								if (!hasAnotherChoice())
								{
									return badSequence();
								}
							}
							break;
						}
						elemIX++;
						if ((ce.occurs & ChildOccurs.oc_allow_many) > 0)
						{
							// more elements might match this
							consumeId(ce.id);
						}
					}
					else if ((ce.occurs & ChildOccurs.oc_one) > 0 && !stacktop.match)
					{
						// optional list sequence, but if occurred, then move up item list
						// sequence may match, and if it does, must complete the sequence?

						if (isNextElementMatch(ce.id))
						{
							elemIX++;
							stacktop.match = true;
							if ((ce.occurs & ChildOccurs.oc_allow_many) > 0)
							{
								consumeId(ce.id);
							}
						}
					}
					else if ((ce.occurs & ChildOccurs.oc_one) > 0)
					{
						// matched one already, must match any others

						if (isNextElementMatch(ce.id) || (child is null))
						{
							estk.pushMsg("missing seq from  " ~ toFelString(edef.flatList,itemIX));
							return false;
						}
						elemIX++;
					}
					else if ((ce.occurs & ChildOccurs.oc_allow_zero) > 0)
					{
						// allowed zeroOne or zeroMany
						// if it is there, must account for it.
						if (isNextElementMatch(ce.id))
						{
							elemIX++;
							if ((ce.occurs & ChildOccurs.oc_allow_many) > 0)
							{
								consumeId(ce.id);
							}
						}
					}
				}
				break;
			default:
				break;
        }
    }
    // consumed the list, if elements still in Items, they are invalid?
    Element remains = nextElement();
    while (remains !is null)
    {
        elemIX++;
        estk.pushMsg(text("Element ",remains.getTagName()," is invalid child"));
        //remains = nextElement();
        return false;

    }
    return true;
}

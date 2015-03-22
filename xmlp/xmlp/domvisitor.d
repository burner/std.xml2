/**
Part of std.xmlp package reimplementation of std.xml (cf.)
Allows a simple loop to do a dom traversal without recursion.

Authors: Michael Rynn
Licence: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.

*/

module xmlp.xmlp.domvisitor;

import xmlp.xmlp.linkdom;
import xmlp.xmlp.parseitem;

/// Keeps track of current element in document, traversed in one direction, depth first

struct ChildElementRange
{
private:
    Node		node_;
    Element		e_;

    void nextElement()
    {
        while(node_ !is null)
        {
            e_ = cast(Element) node_;
            node_ = node_.getNextSibling();
            if (e_ !is null)
                return;
        }
        e_ = null;
    }
public:
    this(Element parent)
    {
        node_ = parent.getFirstChild();
        nextElement();
    }

    @property bool empty()
    {
        return e_ is null;
    }

    @property Element front()
    {
        return e_;
    }

    void popFront()
    {
        nextElement();
    }
}
struct DOMVisitor
{

    private
    {
        Element		parent_;	// parent element
        Node		node_;		// if equals parent, then start or end of element
        int			depth_;		// element depth of parent
        bool		isElement_; // true if node is element
        NodeType	ntype_;
    }

    /// The element whose children are being visited
    @property Element element()
    {
        return parent_;
    }



    private void checkStartElement()
    {
        ntype_ = node_.getNodeType();
        if (ntype_ == NodeType.Element_node)
        {
            depth_++;
            parent_ = cast(Element) node_;
            isElement_ = true;
        }
    }

    private void doEndElement()
    {
        if (depth_ == 0)
        {
            node_ = null;
        }
        else
        {
            depth_--;
            ntype_ = NodeType.Element_node;
            node_ = parent_;
            isElement_ = false;
        }

    }

    /// Current node is an element
    @property bool isElement()
    {
        return isElement_;
    }

    /// NodeType of current node
    @property NodeType nodeType()
    {
        return ntype_;
    }

    /** Indicate travel back up to next sibling of this element,
    without traversing any more of its subtree
    */
    void doneElement()
    {
        doEndElement();
    }

    /** Set the current Element and its depth.
       Depth zero is the depth at which exit will happen for the element.
       If this is the parent element of all the elements to scan, then 0.
       If this was the first of many siblings, then 1 so that exit depth is 0 at parent.
    */

    void startElement(Element e, int elemDepth = 0)
    {
        if (elemDepth < 0)
            elemDepth = 0;
        parent_ = e;
        node_ = e;
        depth_ = elemDepth;
        isElement_ = true;
        ntype_ = NodeType.Element_node;
    }


    /// go to the next node, try children of current element first (depth first)
    bool nextNode()
    {
        if (ntype_ == NodeType.Element_node)
        {
            if (isElement_)
            {
                isElement_ = false;
                node_ = parent_.getFirstChild();
                if (node_ is null)
                {
                    // end of element
                    doEndElement();
                }
                else
                    checkStartElement();
            }
            else   // have done end element
            {
                Node next = node_.getNextSibling();
                if (next !is null)
                {
                    node_ = next;
                    checkStartElement();
                }
                else
                {
                    if (depth_ == 0)
                        return false;
                    depth_--;
                    next = node_.getParentNode();
                    if (next !is null)
                    {
                        parent_ = cast(Element) next;
                        next = next.getNextSibling();
                        if (next !is null)
                        {
                            node_ = next;
                            checkStartElement();
                        }
                        else
                        {
                            doEndElement();
                        }
                    }
                    else
                        return false;
                }
            }
        }
        else
        {
            Node next2 = node_.getNextSibling();
            if (next2 is null)
            {
                parent_ = cast(Element) node_.getParentNode();
                doEndElement();
            }
            else
            {
                node_ = next2;
                checkStartElement();
            }
        }
        return (node_ !is null);
    }
}

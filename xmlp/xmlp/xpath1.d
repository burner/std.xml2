/**
	XPath 1.0 implementation.
	Uses xmlp.xmlp package.


Authors: Michael Rynn
Licence: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Distributed under the Boost Software License, Version 1.0.

Version:  0.1

Support for the 1.0 syntax and abbreviated syntax is still scrappy and lacks enough test examples.
Supports some basic paths and predicate expressions to be useful.

Usage

XPathParser is used to create a PathExpression object from a string.

A PathExpression, is something like Path[Predicate]* Path[Predicate]*...

The PathExpression can be run from Document or Element arguments,
to return a NodeList result, using run function

*/

module xmlp.xmlp.xpath1;

import xmlp.xmlp.charinput;
import std.stdint;
import xmlp.xmlp.xmlchar;
import alt.zstring;
import std.string;
import std.conv;
import std.variant;
import xmlp.xmlp.linkdom;
import xmlp.xmlp.parseitem;
import std.math;

static if (__VERSION__ <= 2053)
{
    import std.ctype;
    alias isdigit isAsciiDigit;
}
else
{
    import std.ascii;
    alias std.ascii.isDigit isAsciiDigit;
}

/**
XPath 1.0 syntax <a href="http://www.w3.org/TR/xpath">XPath 1.0</a>.


1. LocationPath ::= RelativeLocationPath| AbsoluteLocationPath

2. AbsoluteLocationPath ::= '/' RelativeLocationPath?

3. RelativeLocationPath ::= Step | RelativeLocationPath '/' Step | AbbreviatedRelativeLocationPath

4. Step ::= AxisSpecifier NodeTest Predicate*	| AbbreviatedStep

5. AxisSpecifier ::=  AxisName '::' | AbbreviatedAxisSpecifier

6. AxisName ::=
			'ancestor'
			| 'ancestor-or-self'
			| 'attribute'
			| 'child'
			| 'descendant'
			| 'descendant-or-self'
			| 'following'
			| 'following-sibling'
			| 'namespace'
			| 'parent'
			| 'preceding'
			| 'preceding-sibling'
			| 'self'

7.		 NodeTest ::=  NameTest	| NodeType '(' ')'	| 'processing-instruction' '(' Literal ')'
		 NameTest ::=  '*'	| NCName ':' '*' | QName

8.   	Predicate ::=   	'[' PredicateExpr ']'
9.  	PredicateExpr ::=   	Expr


10.   	AbbreviatedAbsoluteLocationPath	::=   	'//' RelativeLocationPath
11.   	AbbreviatedRelativeLocationPath	::=   	RelativeLocationPath '//' Step
12.   	AbbreviatedStep	::= '.' | '..'
13.  	AbbreviatedAxisSpecifier ::= '@'?

14. 	Expr ::= OrExpr
15.   	PrimaryExpr	::= VariableReference
			| '(' Expr ')'
			| Literal
			| Number
			| FunctionCall

16.   	FunctionCall ::= FunctionName '(' ( Argument ( ',' Argument )* )? ')'
17.   	Argument ::=  Expr

18.		UnionExpr	   ::=   	PathExpr | UnionExpr '|' PathExpr
19.   	PathExpr	   ::=   	LocationPath | FilterExpr
								| FilterExpr '/' RelativeLocationPath | FilterExpr '//' RelativeLocationPath
20.   	FilterExpr	   ::=   	PrimaryExpr	| FilterExpr Predicate

21.   	OrExpr	   ::=   	AndExpr	| OrExpr 'or' AndExpr
22.   	AndExpr	   ::=   	EqualityExpr	| AndExpr 'and' EqualityExpr
23.   	EqualityExpr	   ::=   	RelationalExpr	| EqualityExpr '=' RelationalExpr | EqualityExpr '!=' RelationalExpr
24.   	RelationalExpr	   ::=   	AdditiveExpr	| RelationalExpr '<' AdditiveExpr	| RelationalExpr '>' AdditiveExpr
						| RelationalExpr '<=' AdditiveExpr	| RelationalExpr '>=' AdditiveExpr

25.   	AdditiveExpr	   ::=   	MultiplicativeExpr
			| AdditiveExpr '+' MultiplicativeExpr
			| AdditiveExpr '-' MultiplicativeExpr
26.   	MultiplicativeExpr	   ::=   	UnaryExpr
			| MultiplicativeExpr MultiplyOperator UnaryExpr
			| MultiplicativeExpr 'div' UnaryExpr
			| MultiplicativeExpr 'mod' UnaryExpr
27.   	UnaryExpr	   ::=   	UnionExpr	| '-' UnaryExpr

28.   	ExprToken	   ::=   	'(' | ')' | '[' | ']' | '.' | '..' | '@' | ',' | '::'
			| NameTest
			| NodeType
			| Operator
			| FunctionName
			| AxisName
			| Literal
			| Number
			| VariableReference
29.   	Literal	   ::=   	'"' [^"]* '"'
			| "'" [^']* "'"
30.   	Number	   ::=   	Digits ('.' Digits?)?
			| '.' Digits
31.   	Digits	   ::=   	[0-9]+
32.   	Operator	   ::=   	OperatorName
			| MultiplyOperator
			| '/' | '//' | '|' | '+' | '-' | '=' | '!=' | '<' | '<=' | '>' | '>='
33.   	OperatorName	   ::=   	'and' | 'or' | 'mod' | 'div'
34.   	MultiplyOperator	   ::=   	'*'
35.   	FunctionName	   ::=   	QName - NodeType
36.   	VariableReference	   ::=   	'$' QName
37.   	NameTest	   ::=   	'*'	| NCName ':' '*'| QName
38.   	NodeType	   ::=   	'comment'	| 'text'| 'processing-instruction'	| 'node'
39.   	ExprWhitespace	   ::=   	S

*/

/// get a NodeList out of Document using expression
NodeList xpathNodeList(Document d, string pathStr)
{
    XPathParser xpp;

    PathExpression pex = xpp.prepare(pathStr,InitState.IN_PATH);
    return run(pex,d);
}

/// get a NodeList out of Element using expression
NodeList xpathNodeList(Element e, string pathStr)
{
    XPathParser xpp;

    PathExpression pex = xpp.prepare(pathStr,InitState.IN_PATH);
    return run(pex,e);
}

/// use as parse input
alias InputCharRange!dchar ParseSource;

/// PathExpression execution error
class XPathRunError : Error
{
    this(string msg)
    {
        super(msg);
    }
}
/// XPath parser error
class XPathSyntaxError : Error
{
    this(string msg)
    {
        super(msg);
    }
}


enum Axis
{
    Ancestor, AncestorOrSelf,
    Attribute,Child,
    Descendant, DescendantOrSelf,
    Following,FollowingSibling,
    Namespace,Parent,
    Preceding,PrecedingSibling,
    Self
};

alias Array!Variant ValueStack;


/// Part of Predicate expression
struct EvalOp
{
    int		mop;
    int     mop2;
    Variant	data;

    this(int op)
    {
        mop = op;
        mop2 = 0;
    }

    this(int op, ref Variant cdata)
    {
        mop = op;
        mop2 = 0;
        data = cdata;
    }
    this(int op, int op2, ref Variant cdata)
    {
        mop = op;
        mop2 = op2;
        data = cdata;
    }
}

/// Linked parts of Predicate Expression, and expected result
class StepEval
{
    enum
    {
        SE_BOOLEAN,
        SE_INDEX,
        SE_STRING,
    }
    int			evalType;
    StepEval	next;
    EvalOp[]	ops;



};

/// A path step, can have zero or more Predicate expressionss
class PathStep
{
    Axis				axis;
    intptr_t			test;
    string				name;
    StepEval			predicate;
    StepEval			lastPredicate;
    PathStep			next;

    void addEval(StepEval se)
    {
        if (predicate is null)
        {
            predicate = se;
            lastPredicate = se;
        }
        else
        {
            lastPredicate.next = se;
            lastPredicate = se;
        }
    }
}


/// A PathExpression is a number of linked steps.
class PathExpression
{
    bool isAbsolute;
    PathStep	 step;
    PathStep	 last;

    void addStep(PathStep path)
    {
        if (step is null)
        {
            step = path;
            last = path;
        }
        else
        {
            last.next = path;
            last = path;
        }
    }
}

enum NodeNameTest
{
    All, // NameTest
    PrefixAll, // NameTest
    Named // NameTest
}

enum NodeTypeTest
{
    Comment = 3, // Node type
    Text,  // Node type
    ProcessingInstruction,  // Node type
    Node  // Node type
}

enum Operator
{
    opStep, //64
    opAll, //64

    opPipe,//32

    opMultiply,//16
    opDiv,//16
    opMod,//16
    opPlus,//8
    opMinus,//8

    opLess,//4
    opLessEqual,//4
    opMore,//4
    opMoreEqual,//4
    opEqual,//2
    opNotEqual,//2

    opAnd,//1
    opOr,//0
}

enum InitState
{
    IN_PATH,
    IN_AXIS,
    IN_TEST,
    IN_PREDICATE
}

enum EvalOpType
{
    ValNumber = 17,
    ValPath,
    ValString,
    StackInc,
    ValArgument,
    FunctionCall,
    StackPop,
}
const immutable (int)[16] opPrecedence = [
            64,64,32,16,16,16,8,8,4,4,4,4,2,2,1,0
        ];



/** identify the low level token stream
ExprToken	   ::=   	'(' , ')' , '[' | ']' | '.' | '..' | '@' | ',' | '::'
			| NameTest
			| NodeType
			| Operator
			| FunctionName
			| AxisName
			| Literal
			| Number
			| VariableReference
			*/
private enum TokenKind
{
    LParen, RParen, LBrack, RBrack,
    OneDot, TwoDot, AtSign, Comma, Scope,
    NameTest, NodeType, Operator, Function,
    AxisName,Literal, Number, VarRef,
    PathStep, EvalStart,EvalEnd,
    PushStack
}

private struct ExpToken
{
    TokenKind	kind;
    intptr_t	qualifier;
    Variant		vdata;
}

bool isAxisName(const(char)[] name, ref Axis axisType)
{
    switch(name)
    {
    case "ancestor":
        axisType = Axis.Ancestor;
        break;
    case "ancestor-or-self":
        axisType  = Axis.AncestorOrSelf;
        break;
    case "@":
    case "attribute":
        axisType  = Axis.Attribute;
        break;
    case "*":
    case "child":
        axisType = Axis.Child;
        break;
    case "descendant":
        axisType = Axis.Descendant;
        break;
    case "descendant-or-self":
        axisType = Axis.DescendantOrSelf;
        break;
    case "following":
        axisType = Axis.Following;
        break;
    case "following-sibling":
        axisType = Axis.FollowingSibling;
        break;
    case "namespace":
        axisType = Axis.Namespace;
        break;
    case "parent":
        axisType = Axis.Parent;
        break;
    case "preceding":
        axisType = Axis.Preceding;
        break;
    case "preceding-sibling":
        axisType = Axis.PrecedingSibling;
        break;
    case "self":
        axisType = Axis.Self;
        break;
    default:
        return false;
    }
    return true;
}



///chew up usual space characters
bool gotSpace(ParseSource src)
{
    int ct = 0;
    while(!src.empty)
    {
        switch(src.front)
        {
        case 0x20:
        case 0x0A:
        case 0x09:
        case 0x0D:
            src.popFront;
            break;
        default:
            return (ct > 0);
        }
    }
    return (ct > 0);
}






enum XPathConstants
{
    NodeList
};

private struct RunContext
{
    NodeList	nodes;
}

/// The state of the Predicate being evaluated
struct EvalExpression
{
    ValueStack  stack;
    size_t		lastIndex;
    size_t		position;
    Node[]		list;
    Node		contextNode;

    void evalLoop(StepEval se)
    {
        auto pfset = se.ops;
        stack.length = 0;

        for (size_t ix = 0; ix < pfset.length; ix++)
        {
            doOp(pfset[ix]);
        }
    }

    bool evalPredicate(StepEval se, Node[] contextList, size_t proximity)
    {
        auto pfset = se.ops;
        //attrNode = context;
        list = contextList;
        contextNode = list[proximity];

        lastIndex = list.length;
        position = proximity + 1;


        evalLoop(se);
        if (stack.length >= 1)
        {
            Variant r = stack[0];
            auto tid = r.type();
            if (tid == typeid(bool))
                return r.get!bool();
            else if (tid == typeid(size_t))
                return (position == r.get!size_t());
            else if (tid == typeid(double))
                return (position == cast(size_t)r.get!double());
            else
                return false;
        }
        return false;
    }


    void doOp(ref EvalOp op)
    {
        size_t slen = stack.length;
        uint   action = op.mop;
        double numCvt;

        void checkLength2()
        {
            if (slen < 2)
                throw new XPathRunError("Number stack too small");
            // 2 ops, make sure they are same type?

        }

        if (action < EvalOpType.ValNumber)
        {
            // operate on stack

            // TODO: Binary ops only
            switch(opPrecedence[action])
            {
            case 4:
            case 2:
                bool boolResult;
                checkLength2();
                auto op2 = stack[slen-2]; // lhs
                auto op1 = stack[slen-1]; // rhs
                auto type1 = op1.type;
                auto type2 = op2.type;
                bool matched = type1 == type2;
                if (!matched)
                {
                    if (type1 == typeid(double))
                    {
                        if (type2 == typeid(string))
                        {
                            op2 = to!double(op2.get!string());
                            goto OP_ACTION;
                        }
                    }
                    else if (type2 == typeid(double))
                    {
                        if (type1 == typeid(string))
                        {
                            op1 = to!double(op1.get!string());
                            goto OP_ACTION;
                        }
                    }
                    if (type1 == typeid(string))
                    {
                        if (op2.convertsTo!string())
                        {
                            op2 = op2.get!string();
                            goto OP_ACTION;
                        }
                    }
                    else if (type2 == typeid(string))
                    {
                        if (op1.convertsTo!string())
                        {
                            op1 = op1.get!string();
                            goto OP_ACTION;
                        }
                    }
                }

OP_ACTION:
                switch(action)
                {
                case Operator.opEqual:
                    boolResult = op2 == op1;
                    break;
                case Operator.opNotEqual:
                    boolResult = op2 != op1;
                    break;
                case Operator.opLess:
                    boolResult = op2 < op1;
                    break;
                case Operator.opMore:
                    boolResult = op2 > op1;
                    break;
                case Operator.opLessEqual:
                    boolResult = op2 >= op1;
                    break;
                case Operator.opMoreEqual:
                    boolResult = op2 > op1;
                    break;
                default:
                    break;
                }
                slen--;
                stack.length = slen;
                stack [slen-1] = Variant(boolResult);
                break;
            case 8:
            case 16:
                //double doubleResult;
                checkLength2();
                auto op2 = stack[slen-2]; // lhs
                auto op1 = stack[slen-1]; // rhs
                switch(action)
                {
                case Operator.opPlus:
                    op2 += op1;
                    break;
                case Operator.opMinus:
                    op2 -= op1;
                    break;
                case Operator.opMultiply:
                    op2 -= op1;
                    break;
                case Operator.opDiv:
                    op2 /= op1;
                    break;
                case Operator.opMod:
                    op2 %= op1;
                    break;
                default:
                    break;
                }
                slen--;
                stack.length = slen;
                stack[slen-1] = op2;
                //stack[slen-1] = Variant(doubleResult);
                break;
            default:
                break;
            }
        }
        else
        {
            switch(action)
            {
            case EvalOpType.ValNumber:
                stack.put( op.data );
                break;
            case EvalOpType.ValString:
                stack.put( op.data );
                break;
            case EvalOpType.StackInc:
                // a function call is to be made
                // push an empty stack entry for the result.
                stack.put(Variant());
                break;
            case EvalOpType.FunctionCall:
                // call the function
                XPathFunctionCall xfc = op.data.get!XPathFunctionCall();
                auto stackIX = stack.length - op.mop2;
                xfc.execute(this, stackIX);
                stack.length = stackIX;
                break;
            case EvalOpType.ValPath:
                PathExpression pex = op.data.get!PathExpression();
                Element e = cast(Element) contextNode;
                string ndata;
                if (e !is null)
                {
                    NodeList nresult = run(pex, e);
                    if (nresult.getLength > 0)
                    {
                        Node nvalue = nresult.item(0);
                        ndata = (nvalue.getNodeType==NodeType.Element_node) ? nvalue.getTextContent()
                                : nvalue.getNodeValue();
                    }
                }
                stack.put( Variant (ndata) );
                break;
            default:
                throw new XPathRunError("Unhandled op");
            }
        }
    }

}

/// base class used to configure XPath function implementations
class XPathFunctionCall
{
    string  name;
    int		fixedArgCount; // variable if -1
    int		returnType;		// StepEval.SE_BOOLEAN, StepEval.SE_INDEX, StepEval.SE_STRING

    /// construct
    this(string regn, int ct = -1)
    {
        name = regn;
        fixedArgCount = ct;
        XPathFunctionLibrary[name] = this;
    }

    /// examine and manipulate execution context
    bool execute(ref EvalExpression ctx, size_t firstArgIX)
    {
        return false;
    }
}

/// function call and name mapping
alias  XPathFunctionCall[string]	XPathFunctionMap;


class XPathLastFn : XPathFunctionCall
{
    this(string regn)
    {
        super(regn);
        returnType = StepEval.SE_INDEX;
    }
    override bool execute(ref EvalExpression ctx, size_t firstArgIX)
    {
        ctx.stack[firstArgIX - 1] = Variant(ctx.lastIndex);
        return true;
    }
}

/// example implementation, position
class XPathPositionFn : XPathFunctionCall
{
    this(string regn)
    {
        super(regn);
        returnType = StepEval.SE_INDEX;
    }
    override bool execute(ref EvalExpression ctx, size_t firstArgIX)
    {
        ctx.stack[firstArgIX - 1] = Variant(ctx.position);
        return true;
    }
}

/// set up for standard XPath functions
__gshared static XPathFunctionMap	XPathFunctionLibrary;
__gshared static this()
{
    new XPathLastFn("last");
    new XPathPositionFn("position");
}


private struct EvalPathStep
{
    NodeList			source_;
    size_t				slen_;
    Array!Node	result_;
    PathStep			pathStep_;
    string				testName_;
    NodeType			testType_;
    size_t				nodeIX_;
    Array!Node	axisShortList_;
    Element				contextNode_;
    Node				axisNode_;

    NodeList process(NodeList source, PathStep pe)
    {
        source_ = source;
        Node[] takeFrom = source_.items();
        pathStep_ = pe;
        for(size_t i = 0; i < takeFrom.length; i++)
        {
            axisShortList_.length = 0;
            contextNode_ = cast(Element) takeFrom[i];
            if (contextNode_ !is null)
            {

                axisApply();
            }
            if (axisShortList_.length > 0)
                result_.put(axisShortList_.toArray);
        }
        source.setItems(result_.take);
        return source;
    }

    bool axisNodeTest()
    {
        NodeType nt;
        string temp;

        switch(pathStep_.test)
        {
        case NodeTypeTest.Node:	// get all nodes
            return true;
        case NodeTypeTest.Text:
            if (axisNode_.getNodeType == NodeType.Text_node)
                return true;
            break;
        case NodeTypeTest.Comment:
            if (axisNode_.getNodeType == NodeType.Comment_node)
                return true;
            break;
        case NodeTypeTest.ProcessingInstruction:// get all PIs
            if (axisNode_.getNodeType == NodeType.Processing_Instruction_node)
            {
                if (pathStep_.name !is null)
                    return (axisNode_.getNodeName() == pathStep_.name);
                return true;
            }
            break;
        case NodeNameTest.All:
            if (axisNode_.getNodeType ==  NodeType.Element_node)
                return true;
            break;
        case NodeNameTest.Named:
            nt = axisNode_.getNodeType;
            if ( (nt ==  NodeType.Element_node || nt == NodeType.Attribute_node)
                    && (axisNode_.getNodeName() == pathStep_.name))
                return true;
            break;
        case NodeNameTest.PrefixAll: // a *, all element children
            temp = axisNode_.getLocalName();
            if (temp ==  pathStep_.name)
                return true;
            break;
        default:
            break;
        }
        return false;
    }


    void axisApply()
    {
        EvalExpression ee;
        StepEval eval;
        StepEval indexEval = null;
        axisShortList_.length = 0;
        bool doPut = false;
        Element predElement;
        Attr predAttr;
        switch(pathStep_.axis)
        {
        case Axis.Attribute:
            auto nmap = contextNode_.getAttributes();
            if (nmap !is null)
            {
                for(size_t ix = 0; ix < nmap.getLength(); ix++)
                {
                    axisNode_ =  nmap.item(ix);
                    if (axisNodeTest())
                        axisShortList_.put(axisNode_);
                }
            }
            break;
        case Axis.Child:
            axisNode_ = contextNode_.getFirstChild();
            while (axisNode_ !is null)
            {
                if (axisNodeTest())
                    axisShortList_.put(axisNode_);
                axisNode_ = axisNode_.getNextSibling();
            }
            break;
        case Axis.Self:
            // already ourself
            axisShortList_.put(contextNode_);
            break;
        default:
            break;
        }

        eval = pathStep_.predicate;
        while (eval !is null)
        {
            if (axisShortList_.length == 0)
                return;
            Node[] contextList = axisShortList_.take;
            //TODO : axis direction
            for(size_t i = 0; i < contextList.length; i++)
            {
                if (ee.evalPredicate(eval,contextList,i))
                    axisShortList_.put(contextList[i]);
            }
            eval = eval.next;
        }
    }

}

/// run the PathExpression, using element as first context node
NodeList run(PathExpression pex, Element e)
{
    PathStep ps = pex.step;
    NodeList start = new NodeList();
    start ~= e;
    EvalPathStep	eps;
    while(ps !is null)
    {
        start = eps.process(start, ps);
        if (start.getLength()==0)
            break;
        ps = ps.next;
    }
    return start;
}

/// run the PathExpression, using Document as first context node
NodeList run(PathExpression pex, Document d)
{
    if (!pex.isAbsolute)
        throw new XPathSyntaxError("For xpath of document, need absolute path");
    Element eDoc = d.getDocumentElement();
    return run(pex, cast(Element)eDoc.getParentNode());
}

/// XPath object can evaluate multiple expressions, but caches last one used.
class XPath
{
    PathExpression		pathExpression;
    string				expSource;
    Element				current;
    Array!RunContext	stack;

    /*string evaluate(string xp, Document)
    {
    }
    */

    /// resultType crazy because have to return node list anyway.
    NodeList evaluate(string xp, Document d, XPathConstants resultType)
    {
        XPathParser xpp;

        if (xp != expSource)
        {
            pathExpression = xpp.prepare(xp, InitState.IN_PATH);
            expSource = xp;
        }
        return run(pathExpression, d);
    }


}

/// XPath parser data
struct XPathParser
{
    Array!ExpToken toks;
    Array!char	 scratch;
    char[]		temp;
    int			qual;
    TokenKind	op;
    bool		inFunctionArg;
    int 		fnArgCount;

    /// unexpected character encountered
    void ThrowBadChar(dchar xc)
    {
        string msg = format("unhandled character %x :  %s", cast(uint)xc,xc);
        throw new XPathSyntaxError(msg);
    }






    /// parse for a NodeTest
    private void nodeTest(ParseSource src, const(char)[] temp, intptr_t prefix)
    {
        intptr_t qual = -1;
        TokenKind op = TokenKind.NodeType;
        string name;
        Array!char	cbuf;

        if (prefix == temp.length-1)
        {
            // could be NCName:*
            if (src.front == '*')
            {
                src.popFront;
                if (prefix > 0)
                    qual = NodeNameTest.PrefixAll;
                else
                    qual = NodeNameTest.All;

                op = TokenKind.NameTest;
            }
            else
            {
                throw new XPathSyntaxError("Name ends with ':'");
            }
        }
        else
        {
            /// various node types
            if (temp=="node")
                qual = NodeTypeTest.Node;
            else if (temp=="text")
                qual = NodeTypeTest.Text;
            else if (temp=="comment")
                qual = NodeTypeTest.Comment;
            else if (temp=="processing-instruction")
                qual = NodeTypeTest.ProcessingInstruction;
            else
            {
                qual = NodeNameTest.Named;
                op= TokenKind.NameTest;
            }
        }
        if (qual >= 0)
        {
            if (op == TokenKind.NodeType)
            {
                if (!match(src,"("))
                    throw new XPathSyntaxError("Expected '('");
                if (match(src,")"))
                {
                    // no argument
                }
                else
                {
                    // quoted argument
                    if (unquote(src, scratch))
                    {
                        name = scratch.unique;
                    }
                    else
                    {
                        throw new XPathSyntaxError("missing argument after '('");
                    }
                    if (!match(src,")"))
                    {
                        throw new XPathSyntaxError("missing ')'");
                    }
                }
            }
            else
            {
                if (temp.length > 0)
                    name = temp.idup;
            }
            toks.put(ExpToken(op, qual, Variant(name)));
        }
        else
        {
            throw new XPathSyntaxError("Expected Node Test");
        }
    }

    private void getAxis(ParseSource src, bool checkFunction)
    {
        intptr_t prefix;
        Axis axisType = Axis.Child; // default
        bool fetchAgain = false;
TRY_AGAIN:
        switch(src.front)
        {
        case '@':
            src.popFront;
            axisType = Axis.Attribute;
            if (!getQName(src,scratch,prefix))
                ThrowBadChar(src.front);
            break;
        case '.':
            src.popFront;
            if (!src.empty && src.front=='.')
                axisType = Axis.Parent;
            else
                axisType = Axis.Self;
            toks.put(ExpToken(TokenKind.AxisName,axisType));
            if (src.empty)
            {
                toks.put(ExpToken(TokenKind.NodeType, NodeTypeTest.Node));
                return;
            }
            break;
        default:
        {
            if (!getQName(src,scratch,prefix))
            {
                // a * means child::*
                if (!src.empty)
                {
                    dchar checkStar = src.front;
                    if (checkStar == '*')
                    {
                        src.pushFront("child::");
                        goto TRY_AGAIN;
                    }
                }
                ThrowBadChar(src.front);
            }
            if (prefix < 0)
            {
                if (match(src,"::"d))
                {
                    // wants axis name
                    temp = scratch.toArray;
                    if (isAxisName(temp, axisType))
                    {
                        /*if (!match(src,"::"d))
                        	throw new XPathSyntaxError("Expected ::");*/
                        fetchAgain = true;
                    }
                    else
                    {
                        throw new XPathSyntaxError("Expected axis name");
                    }
                }
                else if (checkFunction && match(src,"("))
                {
                    // check XPathFunctionLibrary
                    temp = scratch.toArray;
                    auto fc = temp in XPathFunctionLibrary;
                    if (fc !is null)
                    {

                        // collect function args, terminated by ',' or ')'
                        XPathParser	 sparse;
                        toks.put(ExpToken(TokenKind.PushStack, 1, Variant()));
                        sparse.inFunctionArg = true;
                        sparse.getPredicate(src);
                        toks.put(ExpToken(TokenKind.Function, sparse.fnArgCount, Variant(*fc)));
                        return;
                    }
                }
            }
        }
        break;
        }
        toks.put(ExpToken(TokenKind.AxisName, axisType));
        if (fetchAgain && !getQName(src,scratch,prefix))
        {
            if (!src.empty)
            {
                dchar checkStar = src.front;
                if (checkStar == '*')
                {
                    // all child elements


                }
                else
                    ThrowBadChar(src.front);
            }

        }
        temp = scratch.toArray;
        nodeTest(src, temp, prefix);
    }


    private void doDigits(ParseSource src)
    {
        scratch.length = 0;
        NumberClass nc = parseNumber(src, scratch);

        if ((nc == NumberClass.NUM_REAL)||(nc == NumberClass.NUM_INTEGER))
            toks.put(ExpToken(TokenKind.Number, nc, Variant(scratch.idup)));
        else
            throw new XPathSyntaxError("Invalid number");
    }

    // convert expression into operations
    private void getPredicate(ParseSource src)
    {
        Operator op;
        //ArrayBuffer!char parenStack;
        int parenStack = 0;
        size_t pos;
        intptr_t prefix;
        toks.put(ExpToken(TokenKind.EvalStart));
        size_t	charCount = 0;
        gotSpace(src);
        while(!src.empty)
        {
            charCount++;
            /+
            if (inExpression)
            {
                qual = -1;
                if (temp=="and")
                    qual = Operator.opAnd;
                else if (temp=="or")
                    qual = Operator.opOr;
                else if (temp=="mod")
                    qual = Operator.opMod;
                else if (temp=="div")
                    qual = Operator.opDiv;
                if (qual != -1)
                {
                    toks.put(ExpToken(TokenKind.Operator, qual));
                    doPop = false;
                    break;
                }
                +/
                dchar lastChar = src.front;
                /// TODO: character entities
                switch(lastChar)
                {
                case '(':
                    src.popFront;
                    parenStack++;
                    //parenStack.put(cast(char)lastChar);
                    break;
                case ']':
                    if (parenStack != 0)
                        throw new XPathSyntaxError("Parenthesis mismatch");
                    src.popFront;
                    toks.put(ExpToken(TokenKind.EvalEnd));
                    return;
                case ')':
                    src.popFront;
                    if (parenStack  == 0)
                    {
                        if (inFunctionArg)
                        {
                            charCount--;
                            if (charCount > 0)
                                fnArgCount++;
                            return;
                        }
                        throw new XPathSyntaxError("Parenthesis mismatch");
                    }
                    parenStack--;
                    break;
                case '.':
                    src.popFront;
                    if (!src.empty)
                    {
                        if (isAsciiDigit(src.front))
                        {
                            src.pushFront('.');
                            doDigits(src);
                            break;
                        }
                        if (src.front == '.')
                        {
                            toks.put(ExpToken(TokenKind.AxisName,Axis.Parent));

                        }

                    }
                    toks.put(ExpToken(TokenKind.AxisName,Axis.Self));
                    if (!getQName(src,scratch,prefix))
                        throw new XPathSyntaxError("Expect node test");
                    nodeTest(src,scratch.toArray,prefix);
                    break;
                case '@':
                    src.popFront;
                    toks.put(ExpToken(TokenKind.AxisName,Axis.Attribute));
                    if (!getQName(src,scratch,prefix))
                        throw new XPathSyntaxError("Expect attribute name");
                    nodeTest(src,scratch.toArray,prefix);
                    break;
                case ',':
                    src.popFront;
                    if (inFunctionArg)
                    {
                        fnArgCount++;
                        if (parenStack  != 0)
                        {
                            throw new XPathSyntaxError("Parenthesis mismatch");
                        }

                        toks.put(ExpToken(TokenKind.Function,EvalOpType.ValArgument));
                    }
                    else
                    {
                        throw new XPathSyntaxError("comma not in function call");

                    }

                    break;
                case ':':
                    src.popFront;
                    if (src.empty || src.front != ':')
                        // single ':' do not occur here
                        throw new XPathSyntaxError("missing ':'");
                    toks.put(ExpToken(TokenKind.Scope));
                    break;
                case '$':
                    // variable reference
                    if (getQName(src,scratch,prefix))
                        toks.put(ExpToken(TokenKind.VarRef, prefix, Variant(scratch.idup)));
                    else
                        throw new XPathSyntaxError("Bad VariableReference");
                    break;
                case '\"':
                case '\'':
                    if (!unquote(src,scratch))
                        throw new XPathSyntaxError("Bad Literal");
                    toks.put(ExpToken(TokenKind.Literal, scratch.length, Variant(scratch.idup)));
                    break;
                case '=':
                    src.popFront;
                    toks.put(ExpToken(TokenKind.Operator, Operator.opEqual));
                    break;
                case '<':
                case '>':
                    src.popFront;
                    if (src.front == '=')
                    {
                        op = (lastChar=='<') ? Operator.opLessEqual : Operator.opMoreEqual;
                        src.popFront;
                    }
                    else
                    {
                        op = (lastChar=='<') ? Operator.opLess : Operator.opMore;
                    }
                    toks.put(ExpToken(TokenKind.Operator, op));
                    break;
                case '/':
                    src.popFront;
                    toks.put(ExpToken(TokenKind.Operator, Operator.opDiv));
                    break;
                case '*':
                    src.popFront;
                    toks.put(ExpToken(TokenKind.Operator, Operator.opMultiply));
                    break;
                case '+':
                    src.popFront;
                    toks.put(ExpToken(TokenKind.Operator, Operator.opPlus));
                    break;
                case '-':
                    src.popFront;
                    toks.put(ExpToken(TokenKind.Operator, Operator.opMinus));
                    break;
                    /+
                case '=':

                case '!':

                case '|':
                    +/

                default:
                    // number or path or function
                    if (isWhite(lastChar))
                    {
                        src.popFront;
                        charCount--;
                    }
                    else if (isAsciiDigit(lastChar))
                        doDigits(src);
                    else
                    {

                        getAxis(src, true);
                    }
                    break;
                }
            }
        }

        //TODO : bracket expressions evaluate to single term.
        StepEval toPostfix(ref ExpToken[] src)
        {
            Array!EvalOp	pfset;
            Array!EvalOp	opStack;
            PathStep	step;
            bool isIndex = false;

            while (src.length > 0)
            {
                auto et = &src[0];
                bool doPop = true;
                if (et.kind == TokenKind.EvalEnd)
                {
                    while (opStack.length > 0)
                    {
                        pfset.put(EvalOp(opStack.last.mop));
                        opStack.popBack();
                    }
                    StepEval ev = new StepEval();
                    ev.ops = pfset.take;
                    if (isIndex)
                    {
                        ev.evalType = StepEval.SE_INDEX;
                    }
                    else if (ev.ops.length == 1)
                    {
                        if (EvalOpType.ValNumber == ev.ops[0].mop)
                            ev.evalType = StepEval.SE_INDEX;
                    }
                    else if (ev.ops.length == 2)
                    {
                        if (EvalOpType.FunctionCall == ev.ops[1].mop)
                        {
                            XPathFunctionCall xfc = ev.ops[1].data.get!XPathFunctionCall();
                            ev.evalType = xfc.returnType;
                        }
                    }
                    src = src[1..$];
                    return ev;
                }
                if (et.kind == TokenKind.Operator)
                {
                    Operator op = cast(Operator)et.qualifier;
                    if (opStack.length==0)
                        opStack.put(EvalOp(op));
                    else
                    {
                        // compare precedence
                        auto prev = opStack.last;
                        while (opPrecedence[prev.mop] >= opPrecedence[op])
                        {
                            pfset.put(EvalOp(prev.mop));
                            opStack.popBack();
                            if (opStack.length==0)
                                break;
                            prev = opStack.last;
                        }
                        // now push the operator
                        opStack.put(EvalOp(op));
                    }
                }
                else   // some operand
                {
					Variant arg2;

                    switch(et.kind)
                    {
                    case TokenKind.PathStep:
                    case TokenKind.AxisName:
						arg2= toPath(src);
                        pfset.put(EvalOp(EvalOpType.ValPath, arg2));
                        doPop = false;
                        break;
                    case TokenKind.Literal:
                        pfset.put(EvalOp(EvalOpType.ValString, et.vdata));
                        break;
                    case TokenKind.Number:
                        arg2 = to!double(et.vdata.get!string());
                        pfset.put(EvalOp(EvalOpType.ValNumber, arg2));
                        break;
                    case TokenKind.PushStack:
                        pfset.put(EvalOp(EvalOpType.StackInc));
                        break;
                    case TokenKind.Function:
                        XPathFunctionCall xfc =  et.vdata.get!XPathFunctionCall();
                        if (xfc.returnType == StepEval.SE_INDEX)
                            isIndex = true;
                        pfset.put(EvalOp(cast(int) EvalOpType.FunctionCall,  cast(int) et.qualifier, et.vdata));
                        break;
                    default:
                        throw new XPathSyntaxError("Unhandled token");
                    }
                }
                if (doPop && src.length > 0)
                    src = src[1..$];

            }

            assert(0);
        }

        private PathExpression toPath(ref ExpToken[] src)
        {
            PathExpression result = new PathExpression();
            PathStep	step = null;
            TokenKind	lastKind = TokenKind.AxisName;

            while(src.length > 0)
            {
                auto et = &src[0];
                //TODO : verify sequence of TokenKind for Path
                bool doPop = true;
                switch(et.kind)
                {
                case TokenKind.EvalStart:
                    src = src[1..$];
                    doPop = false;
                    StepEval eval = toPostfix(src);
                    if (eval !is null)
                        step.addEval(eval);
                    //ELSE?
                    break;
                case TokenKind.NameTest:
                    step.name = et.vdata.get!string();
                goto case TokenKind.NodeType;

                case TokenKind.NodeType:
                    assert(lastKind == TokenKind.AxisName);
                    step.test = et.qualifier;
                    if (et.vdata.hasValue)
                        step.name = et.vdata.get!string();
                    break;
                case TokenKind.AxisName:
                    if (lastKind != TokenKind.PathStep)
                    {
                        step = new PathStep();
                        result.addStep(step);
                    }
                    step.axis = cast(Axis)(et.qualifier);
                    break;
                case TokenKind.PathStep:
                    if (step is null)
                    {
                        result.isAbsolute = true;
                    }
                    step = new PathStep();
                    result.addStep(step);
                    break;
                default:
                    return result;
                }
                if (doPop && src.length > 0)
                    src = src[1..$];
                lastKind = et.kind;

            }
            return result;

        }

        /// return a PathExpression from string
        PathExpression prepare(string s, InitState state)
        {
            auto sf = new SliceFill!char(s);
            ParseSource ps = new ParseSource();
            ps.dataSource(sf);

            return prepare(ps,state);
        }
        /// return a PathExpression from  ParseSource
        PathExpression prepare(ParseSource ps, InitState state)
        {
            ps.pumpStart();
            tokenize(ps,  state);
            ExpToken[] src = toks.toArray;
            return toPath(src);
        }
        // expect IN_PATH or IN_PREDICATE
        private void tokenize(ParseSource src, InitState istate)
        {
            int prefix;
            int state = istate;
            toks.length = 0;

            if (istate == InitState.IN_PREDICATE)
            {
                // prefix a Path that indicates the current node context
                toks.put(ExpToken(TokenKind.AxisName, Axis.Self));
                toks.put(ExpToken(TokenKind.NodeType, NodeTypeTest.Node));
            }
            //bool hasAxisSpecifier = false;
            //bool inExpression = false;


            while (!src.empty)
            {
                switch(state)
                {
                case InitState.IN_PATH:
                    switch(src.front)
                    {
                    case '/':
                        toks.put(ExpToken(TokenKind.PathStep));
                        src.popFront;
                        if (src.empty)
                            return;
                        goto default;
                    default:
                        state = InitState.IN_AXIS;
                        break;
                    }
                goto case InitState.IN_AXIS;
                case InitState.IN_AXIS:
                    getAxis(src,false);
                    if (src.front == '[')
                    {
                        state = InitState.IN_PREDICATE;
                        src.popFront;
                    }
                    else
                    {
                        state = InitState.IN_PATH;
                    }
                    break;
                case InitState.IN_PREDICATE:
                    getPredicate(src);
                    state = InitState.IN_PATH;
                    break;
                default:
                    throw new XPathSyntaxError("invalid parse");

                }

            }
            if (istate == InitState.IN_PREDICATE)
                toks.put(ExpToken(TokenKind.EvalEnd));
        }

    }


    unittest
    {




    }







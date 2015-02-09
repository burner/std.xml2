import std.getopt;

import std.ascii : letters, digits, whitespace;
import std.array;
import std.random : Random, uniform;
import std.experimental.logger;

uint seed = 1337;

ulong minDepth = 1;
ulong maxDepth = 100;

ulong minTagLen = 1;
ulong maxTagLen = 100;
double openClose = 0.1;

ulong minAttributeNum = 0;
ulong maxAttributeNum = 30;
ulong minAttributeKey = 0;
ulong maxAttributeKey = 30;
ulong minAttributeValue = 0;
ulong maxAttributeValue = 30;

ulong minChilds = 0;
ulong maxChilds = 10;

double commentRatio = 0.001;
ulong minCommentLen = 1;
ulong maxCommentLen = 100;

ulong minTextLen = 10;
ulong maxTextLen = 1000;

Random random;

string genString(const ulong minLen, const ulong maxLen) @safe {

	auto ret = appender!string();

	immutable ulong len = uniform(minLen, maxLen, random);
	for(ulong i = 0; i < len; ++i) {
		ret.put(letters[uniform(0, letters.length, random)]);
	}

	return ret.data;
}

auto printable = letters ~ digits ~ whitespace;

string getText(Out)(Out output) {
	immutable ulong len = uniform(minTextLen, maxTextLen, random);
}

void genAttributes(Out)(Out output) {
	immutable ulong numAttribute = uniform(minAttributeNum, maxAttributeNum, random);
	for(ulong it = 0; it < numAttribute; ++it) {
		if(it > 0u) {
			output.put(", ");	
		}
		
		output.put(genString(minAttributeKey, maxAttributeKey));
		output.put("=\"");
		output.put(genString(minAttributeValue, maxAttributeValue));
		output.put("\"");
	}
}

void genTag(Out)(Out output, ulong depth) {
	immutable auto tag = genString(minTagLen, maxTagLen); 
	for(ulong indent = 0; indent < depth; ++indent) {
		output.put(' ');
	}
	output.put("<");
	output.put(tag);
	output.put(' ');
	genAttributes(output);
	immutable bool openCloseT = uniform(0.0,1.0,random) < openClose;
	if(openCloseT) {
		output.put("/>\n");
		return;
	} else {
		output.put(">\n");
	}

	immutable ulong numChilds = uniform(minChilds, maxChilds, random);
	immutable ulong nd = uniform(minDepth, maxDepth, random);
	logf("numChilds %3u nd %3u depth %3u", numChilds, nd, depth);
	for(ulong childs = 0; childs < numChilds; ++childs) {
		if(nd > depth) {
			genTag(output, depth+1);
		}
	}

	for(ulong indent = 0; indent < depth; ++indent) {
		output.put(' ');
	}
	output.put("</");
	output.put(tag);
	output.put(">\n");
}

void main(string[] args) {
	import std.stdio : stdout, File;
	string outfile = "outfile.xml";
	auto getoptRslt = getopt(args, 
		"seed|a", &seed,
		"output|r", &outfile,
		"minDepth|b", &minDepth, 
		"maxDepth|c", &maxDepth,
		"minChilds|d", &minChilds, 
		"maxChilds|e", &maxChilds,
		"minTagLen|f", &minTagLen, 
		"maxTagLen|g", &maxTagLen,
		"openClose|s", &openClose,
		"minAttributesNum|i", &minAttributeNum, 
		"maxAttributesNum|j", &maxAttributeNum,
		"minAttributesKey|k", &minAttributeKey, 
		"maxAttributesKey|l", &maxAttributeKey,
		"minAttributesValue|m", &minAttributeValue, 
		"maxAttributesValue|n", &maxAttributeValue,
		"commentRatio|o", &commentRatio,
		"minCommentLen|p", &minCommentLen, 
		"maxCommentLen|q", &maxCommentLen
		);

	if (getoptRslt.helpWanted) {
		defaultGetoptPrinter("Some information about the program.",
	    	getoptRslt.options
		);
		return;
	}

	random = Random(seed);

	auto f = File(outfile, "w");
	genTag(f.lockingTextWriter(), 0u);	
}

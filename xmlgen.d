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

bool syntactic = true;

Random random;

void indent(Out)(Out output, const ulong indent) {
	for(ulong i = 0; i < indent; ++i) {
		output.put(' ');
	}
}

immutable title = ["Azure Mage", "The Splintered Husband", "Touch of Angels",
	 "The Slaves's Search", "The Girlfriend of the Sparks", 
	 "Storms in the Spirits"];

immutable authors = [ "Hans Aanrud", "Alexander Aaronsohn",
	"Héctor Abad Faciolince", "Christopher Abani", "Sait Faik Abasıyanık",
	"Christina Abbey", "Edward Abbey", "Lynn Abbey", "Edwin A. Abbott",
	"Eleanor Hallowell Abbott", "George Frederick Abbott", "Jacob Abbott",
	"John S. C. Abbott", "Mohammed ibn Hajj al-Abdari al-Fasi",
	"Mohammed al-Abdari al-Hihi", "Abdelkrim al-Khattabi",
	"Abd al-Qadir al-Fasi", "Kōbō Abe", "Peter Abelard", "Robert Abernathy",
	"Leila Abouzeid", "Marc Abrahams", "Abu al-Abbas as-Sabti",
	"Abu Imran al-Fasi", "Abu Muqri Mohammed al-Battiwi",
	"Milton Abramowitz", "Mohammed Achaari", "Chinua Achebe",
	"Said Achtouk", "André Aciman", "Forrest J. Ackerman", "Douglas Adams",
	"Robert Adams", "Abd al-Wahhab Adarrak", "Mirza Adeeb",
	"Halide Edip Adıvar"];

void genBooks(Out)(Out output, const ulong depth) {
	indent(output, depth);
	output.put("<Books>\n");

	immutable ulong len = uniform(minChilds, maxChilds, random);
	for(ulong i = 0; i < len; ++i) {
		genBook(output, depth+1);	
	}

	indent(output, depth);
	output.put("</Books>\n");
}

void genBook(Out)(Out output, const ulong depth) {
	indent(output, depth);
	output.put("<Book>\n");

	indent(output, depth);
	output.put("<Author>");
	ulong len = uniform(0, authors.length, random);
	output.put(authors[len]);
	output.put("<Author/>\n");

	indent(output, depth);
	output.put("<Title>");
	len = uniform(0, title.length, random);
	output.put(title[len]);
	output.put("<Title/>\n");
	indent(output, depth);
	output.put("<Title>");
	len = uniform(0, title.length, random);
	output.put(title[len]);
	output.put("<Title/>\n");

	indent(output, depth);
	output.put("<Book/>\n");
}

string genString(const ulong minLen, const ulong maxLen) @safe {
	auto ret = appender!string();

	immutable ulong len = uniform(minLen, maxLen, random);
	for(ulong i = 0; i < len; ++i) {
		ret.put(letters[uniform(0, letters.length, random)]);
	}

	return ret.data;
}

string genString(const ulong minLen, const ulong maxLen, const ulong ind) @safe {
	auto ret = appender!string();

	ulong len = uniform(minLen, maxLen, random);
	indent(ret, ind);
	for(ulong i = 0; i < len; ++i) {
		if(i == 80 - ind) {
			ret.put("\n");
			indent(ret, ind);
		}
		ret.put(letters[uniform(0, letters.length, random)]);
	}
	ret.put("\n");

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
	indent(output, depth);
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

	indent(output, depth);
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
		"maxCommentLen|q", &maxCommentLen,
		"new|t", &syntactic
		);

	if (getoptRslt.helpWanted) {
		defaultGetoptPrinter("Some information about the program.",
	    	getoptRslt.options
		);
		return;
	}

	random = Random(seed);

	auto f = File(outfile, "w");
	if(syntactic) {
		log("There");
		//genTag(f.lockingTextWriter(), 0u);	
	} else {
		log("Here");
		//genBooks(f.lockingTextWriter(), 0u);
	}	
}

import std.getopt;

import std.array;

uint seed = 1337;

ulong minDepth = 1;
ulong maxDepth = 100;

ulong minTagLen = 1;
ulong maxTagLen = 100;
double openClose = 0.1;

ulong minAttribute = 0;
ulong maxAttribute = 100;

double commentRatio = 0.001;
ulong minCommentLen = 1;
ulong maxCommentLen = 100;

string genString(const ulong minLen, const ulong maxLen) @safe {
	import std.ascii : letters;
	import std.random : Random, uniform;

	auto ret = appender!string();

	auto gen = Random(seed);
	ulong len = uniform(minLen, maxLen, gen);
	for(ulong i = 0; i < len; ++i) {
		ret.put(letters[uniform(0, letters.length, gen)]);
	}

	return ret.data;
}

void genTag(Out)(Out output) {
	output.put("<");
	output.put(genString(minTagLen, maxTagLen));
}

void main(string[] args) {
	import std.stdio : stdout;
	auto getoptRslt = getopt(args, 
		"minDepth|i", &minDepth, 
		"maxDepth|a", &maxDepth,
		"minTagLen|n", &minTagLen, 
		"maxTagLen|x", &maxTagLen,
		"openClose|z", &openClose,
		"minAttributes|j", &minAttribute, 
		"maxAttributes|k", &maxAttribute,
		"commentRatio|c", &commentRatio,
		"minCommentLen|l", &minCommentLen, 
		"maxCommentLen|o", &maxCommentLen
		);

	if (getoptRslt.helpWanted) {
		defaultGetoptPrinter("Some information about the program.",
	    	getoptRslt.options
		);
	}

	genTag(stdout.lockingTextWriter());	
}

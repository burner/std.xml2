module runner;

import loggerbenchmark;

import std.getopt;

void main(string[] args) {
	auto getoptRslt = getopt(args);
	if (getoptRslt.helpWanted) {
		defaultGetoptPrinter("Entry Point for benchmarking xml2",
	    	getoptRslt.options
		);
		return;
	}

}

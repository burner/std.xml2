all: xmlgen

xmlgen: xmlgen.d
	dmd -unittest xmlgen.d -ofxmlgen

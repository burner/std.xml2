#include <assert.h>
#include <rapidxml.hpp>
#include <iostream>
#include <fstream>
#include <streambuf>
#include <string>
#include <vector>

using namespace rapidxml;

int main(int argc, char** argv) {
	std::ifstream t(argv[1]);
	std::vector<char> str((std::istreambuf_iterator<char>(t)), 
		std::istreambuf_iterator<char>());
	str.push_back('\0');
	xml_document<> doc;

	try {
		doc.parse<0>(&str[0]);
		return 0;
	} catch(parse_error& e) {
		std::cout<<e.what()<<std::endl;
		std::cout<<reinterpret_cast<int*>(e.where<int>())-(int*)&str[0]<<std::endl;
		return 1;
	}

	assert(false);
}

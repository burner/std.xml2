module std.xml2.lexer;

import std.typecons : Flags;

alias TrackPosition = Flags!"TrackPosition";

struct SourcePostion(TrackPosition track) {
	static if(track) {
		uint line;
		uint column;
	}

	void advance(C)(C c) {
		static if(track) {

		}
	}
}

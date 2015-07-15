module std.xml2.exceptions;

import std.exception;

class XMLException : Exception {
	this(string msg, string file = __FILE__, int line = __LINE__) {
		super(msg, file, line);
	}

    this(string msg, string file = __FILE__, size_t line = __LINE__,
         Throwable next = null) @safe pure
    {
        super(msg, file, line, next);
	}

	this(XMLException old) {
		super(old.msg, old.file, old.line, old.next);
	}
}

final class XMLEmptyInputException : XMLException {
    this(string msg, string file = __FILE__, size_t line = __LINE__,
         Throwable next = null) @safe pure
    {
        super(msg, file, line, next);
    }
}

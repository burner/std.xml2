module xmlp.xmlp.fastinfoset;

/**
	Out of interest, an implementation to read and write a DOM using a fast infoset.
	Based on my reading of http://www.itu.int/ITU-T/asn1/xml/finf.htm
	Fast Infoset documents are described as a bit stream.

	A fast infoset may start
	<?xml encoding='finf'?>
	<?xml encoding='finf'? standalone='yes'|'no'?>
	<?xml version='1.x' encoding='finf'?>
	<?xml version='1.x' encoding='finf'standalone='yes'|'no'?>
*/

import std.bitmanip;

/// beginning of every fast infoset, unless preceded by xml declaration
immutable(ubyte)[]  Octet0 = [ 0xe0, 0x00 ];
immutable(ubyte)[]  Octet2 = [ 0x00, 0x01 ];  // version number

/// In order of bitstream, back to front on value
enum DocumentOptions {
	zeroBit = 128,
	additionalData = 64,
	initialVocabulary = 32,
	notations = 16,
	unparsedEntities = 8,
	characterEncodingScheme = 4,
	standalone = 2,
	versionXml = 1
}

enum OctetStringBit2 {
	size6 = 0,
	size8 = 2,
	size32 = 3
}

/// read encoded length starting on bitstream 2
uint readLength2(ref const(ubyte)[] src)
{
	uint result = (src[0] & 0x7F); // mask off sig bit
	if ((result & 0x40 ) == 0)
	{

		result++;// range is 1 to 64
		src = src[1..$];
	}
	else if ((result & 0x20) == 0) // next 8 bits
	{
		result = src[1] + 65;// range is 65 to 320
		src = src[2..$];
	}
	else {
		// next 32 bits
		ubyte[4] bits = src[1..5];
		result = bigEndianToNative!(uint, uint.sizeof )(bits) + 321;// range is 321 to 2^32
		src = src[5..$];
	}
	return result;
}

uint readSequenceLength(ref const(ubyte)[] src)
{
	uint result = src[0];
	if ((result & 0x80 ) == 0)
	{
		result++;// range is 1 to 128
		src = src[1..$];
	}
	else {
		result &= 0xF; // top 4 bits.
		ubyte bits[2] = src[1..3];
		ushort bottom = bigEndianToNative!(ushort,ushort.sizeof)(bits);
		result = (result << 16) + bottom + 129;
		src = src[3..$];
	}
	return result;
}

enum DocumentFIS {
	IdentIndex,
	NonIdentIndex,
	QualIndex,
	NamespaceIndex,
	PrefixIndex,
	LocalIndex
}
